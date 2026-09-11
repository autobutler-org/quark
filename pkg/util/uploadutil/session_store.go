package uploadutil

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"log"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// stagingDirName is the directory, under the data dir's tmp area, where
// partial uploads accumulate. It is deliberately outside the files
// namespace: a partial upload must never be listable as a real file.
const stagingDirName = "upload-sessions"

// session is one file in flight. Everything above the mutex is fixed when the
// session is created; everything below it moves as chunks arrive.
type session struct {
	id        string
	rootDir   string
	fileName  string
	totalSize int64
	serial    string
	overwrite bool
	tempPath  string
	createdAt time.Time
	expiresAt time.Time

	mu     sync.Mutex
	file   *os.File
	offset int64
	closed bool
}

// CreateSession validates the upload and stages an empty temp file for it.
// Validation happens here rather than in the handler so the same guards apply
// to any future caller — and so a traversal attempt is refused before a single
// byte is staged, instead of after gigabytes have been written.
func (s *SessionStore) CreateSession(params CreateSessionParams) (CreateSessionResult, error) {
	// Structure travels in rootDir, never in the filename (#1603). The same
	// filepath.Base the multipart path applies is applied here, and again at
	// commit time, so removing either one does not reopen the hole.
	const fileNameCurrentDir = "."
	fileName := filepath.Base(strings.TrimSpace(params.FileName))
	if fileName == fileNameCurrentDir || fileName == ".." || fileName == string(filepath.Separator) {
		return CreateSessionResult{}, fmt.Errorf("%w: fileName is required", ErrInvalidRequest)
	}
	if params.TotalSize <= 0 {
		return CreateSessionResult{}, fmt.Errorf(
			"%w: totalSize must be greater than zero, got %d", ErrInvalidRequest, params.TotalSize)
	}
	rootDir, err := cleanRootDir(params.RootDir)
	if err != nil {
		return CreateSessionResult{}, err
	}
	if !params.Destination.Writable(params.Serial) {
		return CreateSessionResult{}, ErrNoDestination
	}

	id, err := newSessionID()
	if err != nil {
		return CreateSessionResult{}, err
	}
	if err := os.MkdirAll(s.stagingDir, 0o755); err != nil {
		return CreateSessionResult{}, fmt.Errorf("failed to create upload staging directory: %w", err)
	}
	file, err := os.CreateTemp(s.stagingDir, "upload-*.part")
	if err != nil {
		return CreateSessionResult{}, fmt.Errorf("failed to stage upload: %w", err)
	}

	const createdOffset = 0
	now := time.Now()
	sess := &session{
		id:        id,
		rootDir:   rootDir,
		fileName:  fileName,
		totalSize: params.TotalSize,
		serial:    params.Serial,
		overwrite: params.Overwrite,
		tempPath:  file.Name(),
		createdAt: now,
		expiresAt: now.Add(s.ttl),
		file:      file,
		offset:    createdOffset,
	}

	s.mu.Lock()
	s.sessions[id] = sess
	s.mu.Unlock()

	return CreateSessionResult{
		SessionID: id,
		Offset:    createdOffset,
		ExpiresAt: sess.expiresAt,
	}, nil
}

// WriteChunk appends one chunk and, when the file is whole, moves it into the
// namespace. The server appends and never seeks: a chunk that does not start
// exactly at the committed offset is refused with that offset attached, so the
// client resyncs rather than punching a hole in the file.
func (s *SessionStore) WriteChunk(params WriteChunkParams) (WriteChunkResult, error) {
	sess, err := s.lookup(params.SessionID)
	if err != nil {
		return WriteChunkResult{}, err
	}
	if params.Range.Total != sess.totalSize {
		return WriteChunkResult{}, fmt.Errorf(
			"%w: range declares a %d byte file but the session was opened for %d",
			ErrInvalidRange, params.Range.Total, sess.totalSize)
	}

	// Held across the whole write: two chunks racing on one session would
	// otherwise interleave at the same offset and corrupt the file.
	sess.mu.Lock()
	defer sess.mu.Unlock()
	if sess.closed {
		return WriteChunkResult{}, fmt.Errorf("%w: %q", ErrSessionNotFound, params.SessionID)
	}

	switch {
	case params.Range.End < sess.offset:
		// Entirely below the committed offset: this chunk was accepted before
		// and its response was lost on the way back. Answering 409 here would
		// strand a client that is doing exactly the right thing, so the write
		// is skipped and the current offset returned.
	case params.Range.Start != sess.offset:
		return WriteChunkResult{}, &OffsetMismatchError{Start: params.Range.Start, Offset: sess.offset}
	default:
		if err := sess.append(params.Range, params.Body); err != nil {
			return WriteChunkResult{}, err
		}
	}

	if sess.offset < sess.totalSize {
		return WriteChunkResult{SessionID: sess.id, Offset: sess.offset}, nil
	}
	// Every byte is staged. A replayed final chunk lands here too, which is
	// what makes a commit that failed on a full disk retryable: the client
	// resends the last chunk and the move into the namespace is attempted
	// again, rather than the session sitting complete-but-unwritten until it
	// expires.
	return s.commit(params.Ctx, sess, params.Destination)
}

// DescribeSession is the resync path: after a dropped connection the client
// asks what landed instead of guessing.
func (s *SessionStore) DescribeSession(params DescribeSessionParams) (DescribeSessionResult, error) {
	sess, err := s.lookup(params.SessionID)
	if err != nil {
		return DescribeSessionResult{}, err
	}
	sess.mu.Lock()
	defer sess.mu.Unlock()
	if sess.closed {
		return DescribeSessionResult{}, fmt.Errorf("%w: %q", ErrSessionNotFound, params.SessionID)
	}
	return DescribeSessionResult{
		SessionID: sess.id,
		Offset:    sess.offset,
		TotalSize: sess.totalSize,
		FileName:  sess.fileName,
		RootDir:   sess.rootDir,
		ExpiresAt: sess.expiresAt,
	}, nil
}

// DeleteSession drops a session and its staged bytes. Clients fire this when
// the user cancels, so the disk comes back immediately instead of at the TTL.
func (s *SessionStore) DeleteSession(params DeleteSessionParams) (DeleteSessionResult, error) {
	s.mu.Lock()
	sess, ok := s.sessions[params.SessionID]
	delete(s.sessions, params.SessionID)
	s.mu.Unlock()

	if !ok {
		return DeleteSessionResult{}, fmt.Errorf("%w: %q", ErrSessionNotFound, params.SessionID)
	}
	sess.discard()
	return DeleteSessionResult{}, nil
}

// Sweep expires every session past its deadline and deletes the bytes it
// staged. Without it an abandoned upload leaks its temp file forever, which on
// a device holding photo libraries is the difference between a full disk and a
// working one.
//
// It takes the clock rather than reading it so a test can force expiry outright
// instead of sleeping through a TTL.
func (s *SessionStore) Sweep(now time.Time) SweepResult {
	s.mu.Lock()
	expired := make([]*session, 0, len(s.sessions))
	for id, sess := range s.sessions {
		if now.After(sess.expiresAt) {
			expired = append(expired, sess)
			delete(s.sessions, id)
		}
	}
	s.mu.Unlock()

	// Deliberately outside the store lock: discard closes and unlinks files,
	// and it takes each session's own lock, which a chunk write may be holding.
	for _, sess := range expired {
		sess.discard()
	}
	return SweepResult{Expired: len(expired)}
}

// StartSweeper runs Sweep on a ticker until ctx is cancelled, then drops every
// remaining session. Called once from server startup — never from a
// constructor, so building a dependency graph in a test does not leave a
// goroutine behind.
func (s *SessionStore) StartSweeper(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = DefaultSweepInterval
	}
	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				s.Close()
				return
			case now := <-ticker.C:
				if result := s.Sweep(now); result.Expired > 0 {
					log.Printf("[upload] swept %d expired upload session(s)", result.Expired)
				}
			}
		}
	}()
}

// Close drops every session and its staged bytes. Sessions do not survive a
// restart, so leaving the files behind would only strand them.
func (s *SessionStore) Close() error {
	s.mu.Lock()
	remaining := make([]*session, 0, len(s.sessions))
	for id, sess := range s.sessions {
		remaining = append(remaining, sess)
		delete(s.sessions, id)
	}
	s.mu.Unlock()

	for _, sess := range remaining {
		sess.discard()
	}
	return nil
}

// StagingDir is where partial uploads accumulate. Exported for tests that check
// nothing is left behind.
func (s *SessionStore) StagingDir() string {
	return s.stagingDir
}

// lookup resolves a session id, expiring the session on the way past if its
// deadline has gone by. Lazy expiry means a session cannot be resumed between
// its deadline and the next sweep, which would otherwise be a window of up to
// DefaultSweepInterval.
func (s *SessionStore) lookup(id string) (*session, error) {
	s.mu.Lock()
	sess, ok := s.sessions[id]
	expired := ok && time.Now().After(sess.expiresAt)
	if expired {
		delete(s.sessions, id)
	}
	s.mu.Unlock()

	if !ok {
		return nil, fmt.Errorf("%w: %q", ErrSessionNotFound, id)
	}
	if expired {
		sess.discard()
		return nil, fmt.Errorf("%w: %q has expired", ErrSessionNotFound, id)
	}
	return sess, nil
}

// commit moves a fully staged file into the namespace. Called with the
// session's lock held.
func (s *SessionStore) commit(ctx context.Context, sess *session, dest Destination) (WriteChunkResult, error) {
	if err := sess.file.Sync(); err != nil {
		return WriteChunkResult{}, fmt.Errorf("failed to flush staged upload: %w", err)
	}
	if _, err := sess.file.Seek(0, io.SeekStart); err != nil {
		return WriteChunkResult{}, fmt.Errorf("failed to rewind staged upload: %w", err)
	}

	// SourcePath lets a host-backed namespace rename the staged file into
	// place rather than copy it (#1828). sess.file stays open across the move —
	// on the platforms we build for an open file can be renamed — so a failed
	// commit can still be retried, and discardLocked closes it afterwards.
	written, err := dest.WriteFile(WriteFileParams{
		Ctx:        ctx,
		Reader:     sess.file,
		SourcePath: sess.tempPath,
		RootDir:    sess.rootDir,
		FileName:   sess.fileName,
		Serial:     sess.serial,
		Overwrite:  sess.overwrite,
	})
	if err != nil {
		// The session survives so the client can retry the last chunk; the
		// staged bytes are still valid and re-staging gigabytes to work around
		// a transient disk error would be the wrong trade.
		return WriteChunkResult{}, err
	}

	s.mu.Lock()
	delete(s.sessions, sess.id)
	s.mu.Unlock()
	sess.discardLocked()

	return WriteChunkResult{
		SessionID: sess.id,
		Offset:    sess.offset,
		Complete:  true,
		Path:      written.Path,
	}, nil
}

// append writes one chunk at the committed offset. Called with the session's
// lock held.
func (sess *session) append(chunk ContentRange, body io.Reader) error {
	if _, err := sess.file.Seek(sess.offset, io.SeekStart); err != nil {
		return fmt.Errorf("failed to seek staged upload: %w", err)
	}

	want := chunk.Length()
	got, err := io.CopyN(sess.file, body, want)
	if err != nil || got != want {
		// Either the client lied about the length or the connection died
		// mid-chunk. Both mean the staged file now ends somewhere the client
		// does not expect, so it is cut back to the last committed byte and the
		// chunk is refused; the client resends from an offset that is still true.
		sess.rollback()
		return fmt.Errorf("%w: chunk body carried %d of the declared %d bytes", ErrInvalidRange, got, want)
	}

	// A body longer than its declared range means the two sides disagree about
	// what was just committed. Silently dropping the tail would leave that
	// disagreement in the file.
	var probe [1]byte
	if extra, _ := body.Read(probe[:]); extra > 0 {
		sess.rollback()
		return fmt.Errorf("%w: chunk body is longer than the declared %d bytes", ErrInvalidRange, want)
	}

	sess.offset += got
	return nil
}

// rollback cuts the staged file back to the committed offset after a failed
// chunk. Best effort: if the truncate itself fails there is nothing better to
// try, and the mismatch surfaces on the next chunk as a 409 the client can act on.
func (sess *session) rollback() {
	if err := sess.file.Truncate(sess.offset); err != nil {
		log.Printf("[upload] failed to roll back session %s to offset %d: %v", sess.id, sess.offset, err)
	}
}

// discard closes the staged file and unlinks it.
func (sess *session) discard() {
	sess.mu.Lock()
	defer sess.mu.Unlock()
	sess.discardLocked()
}

// discardLocked is discard for callers already holding the session lock.
func (sess *session) discardLocked() {
	if sess.closed {
		return
	}
	sess.closed = true
	if err := sess.file.Close(); err != nil {
		log.Printf("[upload] failed to close staged upload %s: %v", sess.tempPath, err)
	}
	if err := os.Remove(sess.tempPath); err != nil && !os.IsNotExist(err) {
		log.Printf("[upload] failed to remove staged upload %s: %v", sess.tempPath, err)
	}
}

// cleanRootDir applies the traversal guard the multipart upload gets from
// storageutil.SafeJoin, only earlier: at session creation, before any byte is
// staged, instead of at the write that would have escaped. The base is a
// sentinel because the real files directory is not known until the commit picks
// a destination — the check being done is "can this path climb out", which is
// independent of what it climbs out of.
func cleanRootDir(rootDir string) (string, error) {
	const sentinelRoot = "/upload-root"

	trimmed := strings.Trim(strings.TrimSpace(rootDir), "/")
	if trimmed == "" {
		return "", nil
	}
	if _, err := storageutil.SafeJoin(sentinelRoot, trimmed); err != nil {
		return "", fmt.Errorf("%w: rootDir %q escapes the upload root", ErrInvalidRequest, rootDir)
	}
	return path.Clean(trimmed), nil
}

// newSessionID returns an opaque, URL-safe id. It has to be unguessable: the id
// is the only thing standing between one user's in-flight upload and another
// caller appending to it, so a counter or a timestamp will not do.
func newSessionID() (string, error) {
	const idBytes = 16
	var buf [idBytes]byte
	if _, err := rand.Read(buf[:]); err != nil {
		return "", fmt.Errorf("failed to generate upload session id: %w", err)
	}
	return hex.EncodeToString(buf[:]), nil
}
