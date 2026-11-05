package uploadutil

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// stagingDirName is the directory, under a device data dir's tmp area, where
// partial uploads accumulate. It is deliberately outside the files
// namespace: a partial upload must never be listable as a real file.
const stagingDirName = "upload-sessions"

// stagingPattern names staged uploads. Clearing a staging dir removes only
// these.
const stagingPattern = "upload-*.part"

// session is one file in flight. Everything above the mutex is fixed when the
// session is created; everything below it moves as chunks arrive.
type session struct {
	id        string
	rootDir   string
	fileName  string
	totalSize int64
	serial    string
	overwrite bool
	keepBoth  bool
	// userID is who opened the session; nobody else can see or use it.
	userID    int64
	tempPath  string
	createdAt time.Time
	expiresAt time.Time

	// committed mirrors offset, and updatedAt (Unix nanoseconds) is when the
	// last chunk landed. Both are atomics so ListSessions can read them without
	// taking mu, which a chunk write or a commit holds for as long as the disk
	// takes.
	committed  atomic.Int64
	updatedAt  atomic.Int64
	committing atomic.Bool

	mu     sync.Mutex
	file   *os.File
	offset int64
	closed bool
	// lastProgress is when a chunk last reported ProgressDue.
	lastProgress time.Time
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
	if params.Overwrite && params.KeepBoth {
		return CreateSessionResult{}, fmt.Errorf("%w: choose overwrite or keepBoth, not both", ErrInvalidRequest)
	}
	if !params.Destination.Writable(params.Serial) {
		return CreateSessionResult{}, ErrNoDestination
	}
	// A taken name is answered now, before the client sends a byte, rather
	// than after it has sent gigabytes. The commit checks again.
	if !params.Overwrite && !params.KeepBoth &&
		params.Destination.taken(orBackground(params.Ctx), params.Serial, rootDir, fileName) {
		return CreateSessionResult{}, fmt.Errorf("%w: %s", vfs.ErrConflict, path.Join(rootDir, fileName))
	}

	id, err := newSessionID()
	if err != nil {
		return CreateSessionResult{}, err
	}
	stagingDir, err := s.stagingDirFor(orBackground(params.Ctx), params.Destination, params.Serial)
	if err != nil {
		return CreateSessionResult{}, err
	}
	file, err := os.CreateTemp(stagingDir, stagingPattern)
	if err != nil {
		return CreateSessionResult{}, fmt.Errorf("failed to stage upload: %w", err)
	}

	const createdOffset = 0
	now := s.now()
	sess := &session{
		id:        id,
		rootDir:   rootDir,
		fileName:  fileName,
		totalSize: params.TotalSize,
		serial:    params.Serial,
		overwrite: params.Overwrite,
		keepBoth:  params.KeepBoth,
		userID:    params.UserID,
		tempPath:  file.Name(),
		createdAt: now,
		expiresAt: now.Add(s.ttl),
		file:      file,
		offset:    createdOffset,
		// The first progress hint comes ProgressInterval after the start,
		// not on the first chunk: creating the session is its own news.
		lastProgress: now,
	}
	sess.updatedAt.Store(now.UnixNano())

	if err := s.admit(sess); err != nil {
		sess.discard()
		return CreateSessionResult{}, err
	}

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
	sess, err := s.lookup(params.SessionID, params.UserID)
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
	// A USB drive unplugged mid-upload took the staged file with it, so the
	// session can never finish. It ends now, and the client is told there is
	// nowhere for the file to go, rather than writing on to a dead file.
	if sess.serial != "" && params.Destination.gone(orBackground(params.Ctx), sess.serial) {
		err := fmt.Errorf("%w: device %q: %w", ErrNoDestination, sess.serial, vfs.ErrNotFound)
		s.endLocked(sess, SessionFailed, err.Error())
		s.forgetStagingDir(filepath.Dir(sess.tempPath))
		return WriteChunkResult{}, err
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
		sess.committed.Store(sess.offset)
		sess.updatedAt.Store(s.now().UnixNano())
	}

	if sess.offset < sess.totalSize {
		now := s.now()
		due := now.Sub(sess.lastProgress) >= ProgressInterval
		if due {
			sess.lastProgress = now
		}
		return WriteChunkResult{SessionID: sess.id, Offset: sess.offset, ProgressDue: due}, nil
	}
	// Every byte is staged. A replayed final chunk lands here too, which is
	// what makes a commit that failed on a full disk retryable: the client
	// resends the last chunk and the move into the namespace is attempted
	// again, rather than the session sitting complete-but-unwritten until it
	// expires.
	return s.commit(sess, params)
}

// DescribeSession is the resync path: after a dropped connection the client
// asks what landed instead of guessing.
func (s *SessionStore) DescribeSession(params DescribeSessionParams) (DescribeSessionResult, error) {
	sess, err := s.lookup(params.SessionID, params.UserID)
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
	// Someone else's session is left alone and reported as missing, the same
	// as one that never existed.
	ok = ok && sess.userID == params.UserID
	if ok {
		delete(s.sessions, params.SessionID)
		s.recordLocked(sess, SessionCanceled, "")
	}
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
			s.recordLocked(sess, SessionExpired, "")
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

// ListSessions reports the caller's upload sessions: every one in flight and
// the ones that ended in the last FinishedSessionMaxAge. It reads only what a
// session keeps in atomics, so a chunk write or a slow commit never holds it up.
func (s *SessionStore) ListSessions(params ListSessionsParams) ListSessionsResult {
	now := s.now()
	s.mu.Lock()
	defer s.mu.Unlock()

	var result ListSessionsResult
	for _, sess := range s.sessions {
		if sess.userID == params.UserID {
			result.Active = append(result.Active, sess.summary(sess.liveState(), time.Unix(0, sess.updatedAt.Load()), ""))
		}
	}
	slices.SortFunc(result.Active, func(a, b SessionSummary) int { return a.CreatedAt.Compare(b.CreatedAt) })

	kept := s.finished[params.UserID][:0]
	for _, ended := range s.finished[params.UserID] {
		if now.Sub(ended.UpdatedAt) <= FinishedSessionMaxAge {
			kept = append(kept, ended)
		}
	}
	if len(kept) == 0 {
		delete(s.finished, params.UserID)
	} else {
		s.finished[params.UserID] = kept
	}
	for i := len(kept) - 1; i >= 0; i-- {
		result.Finished = append(result.Finished, kept[i])
	}
	return result
}

// recordLocked keeps how a session ended for ListSessions. Called with s.mu
// held.
func (s *SessionStore) recordLocked(sess *session, state SessionState, errText string) {
	ended := append(s.finished[sess.userID], sess.summary(state, s.now(), errText))
	if extra := len(ended) - MaxFinishedSessionsPerUser; extra > 0 {
		ended = slices.Delete(ended, 0, extra)
	}
	s.finished[sess.userID] = ended
}

// StagingDir is where partial uploads accumulate. Exported for tests that check
// nothing is left behind.
func (s *SessionStore) StagingDir() string {
	return s.stagingDir
}

// stagingDirFor is where a session for this serial stages. A USB drive's
// session stages on that drive, beside its files, so the commit is a rename
// on one filesystem rather than a copy off the internal drive (#3970). The
// internal drive, and a namespace that cannot take a file by rename, use the
// store's own dir. A drive that is gone is ErrNoDestination.
func (s *SessionStore) stagingDirFor(ctx context.Context, dest Destination, serial string) (string, error) {
	dir := s.stagingDir
	var err error
	if mover, ok := dest.FilesVFS(serial).(vfs.FileMover); ok && serial != "" {
		dir, err = mover.StagingDir(ctx, stagingDirName)
	} else {
		err = os.MkdirAll(dir, 0o755)
	}
	if errors.Is(err, vfs.ErrNotFound) {
		return "", fmt.Errorf("%w: device %q: %w", ErrNoDestination, serial, err)
	}
	if err != nil {
		return "", fmt.Errorf("failed to create upload staging directory: %w", err)
	}
	s.clearStranded(dir)
	return dir, nil
}

// clearStranded removes the staged uploads an earlier process left in dir,
// the first time this store stages there. Sessions live in memory, so a
// process that died mid-upload stranded its files, and on a USB drive nothing
// else clears them: the startup wipe covers only the internal data dir. Until
// the clear is done no session of this store has staged in dir, so every
// staged upload in it belongs to an earlier process.
func (s *SessionStore) clearStranded(dir string) {
	s.stagingMu.Lock()
	defer s.stagingMu.Unlock()
	if s.prepared[dir] {
		return
	}
	s.prepared[dir] = true
	// Glob fails only on a malformed pattern, and stagingPattern is constant.
	stranded, _ := filepath.Glob(filepath.Join(dir, stagingPattern))
	for _, p := range stranded {
		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
			log.Printf("[upload] failed to remove stranded upload %s: %v", p, err)
		}
	}
	if len(stranded) > 0 {
		log.Printf("[upload] cleared %d stranded upload(s) from %s", len(stranded), dir)
	}
}

// forgetStagingDir has the next session in dir clear it again. A drive
// unplugged mid-upload keeps the staged files its sessions could not remove,
// and the next session after it is plugged back in clears them.
func (s *SessionStore) forgetStagingDir(dir string) {
	s.stagingMu.Lock()
	delete(s.prepared, dir)
	s.stagingMu.Unlock()
}

// lookup resolves a session id for the user asking, expiring the session on
// the way past if its deadline has gone by. Lazy expiry means a session cannot
// be resumed between its deadline and the next sweep, which would otherwise be
// a window of up to DefaultSweepInterval. A session opened by someone else is
// not found, and is neither expired nor touched on their behalf.
func (s *SessionStore) lookup(id string, userID int64) (*session, error) {
	s.mu.Lock()
	sess, ok := s.sessions[id]
	ok = ok && sess.userID == userID
	expired := ok && s.now().After(sess.expiresAt)
	if expired {
		delete(s.sessions, id)
		s.recordLocked(sess, SessionExpired, "")
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

// admit adds a new session unless that would put its owner past
// MaxSessionsPerUser or the store past MaxSessions. Sessions already past
// their deadline are dropped first, so an abandoned upload holds no slot
// between its deadline and the next sweep.
func (s *SessionStore) admit(sess *session) error {
	s.mu.Lock()
	var expired []*session
	owned := 0
	for id, other := range s.sessions {
		switch {
		case sess.createdAt.After(other.expiresAt):
			expired = append(expired, other)
			delete(s.sessions, id)
			s.recordLocked(other, SessionExpired, "")
		case other.userID == sess.userID:
			owned++
		}
	}
	full := owned >= MaxSessionsPerUser || len(s.sessions) >= MaxSessions
	if !full {
		s.sessions[sess.id] = sess
	}
	s.mu.Unlock()

	// Outside the store lock, as in Sweep.
	for _, other := range expired {
		other.discard()
	}
	if full {
		return ErrTooManySessions
	}
	return nil
}

// commit moves a fully staged file into the namespace. Called with the
// session's lock held.
func (s *SessionStore) commit(sess *session, params WriteChunkParams) (WriteChunkResult, error) {
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
	sess.committing.Store(true)
	defer sess.committing.Store(false)
	beforeOverwrite := params.BeforeOverwrite
	if sess.serial != "" {
		beforeOverwrite = nil
	}
	written, err := params.Destination.WriteFile(WriteFileParams{
		Ctx:             params.Ctx,
		Reader:          sess.file,
		SourcePath:      sess.tempPath,
		RootDir:         sess.rootDir,
		FileName:        sess.fileName,
		Serial:          sess.serial,
		Overwrite:       sess.overwrite,
		KeepBoth:        sess.keepBoth,
		BeforeOverwrite: beforeOverwrite,
	})
	if err != nil {
		// A transient failure (I/O, a full disk, a dropped request) keeps the
		// session so the client can resend the last chunk; re-staging gigabytes
		// to work around it would be the wrong trade. A failure no retry can
		// fix ends the session now rather than holding a full copy of the file
		// on disk until the TTL.
		if commitCannotSucceed(err) {
			s.endLocked(sess, SessionFailed, err.Error())
		}
		return WriteChunkResult{}, err
	}
	s.endLocked(sess, SessionCompleted, "")

	return WriteChunkResult{
		SessionID: sess.id,
		Offset:    sess.offset,
		Complete:  true,
		Path:      written.Path,
		Serial:    sess.serial,
		Created:   written.Created,
	}, nil
}

// endLocked removes a session from the store, records how it ended, and
// discards its staged file. Called with the session's lock held.
func (s *SessionStore) endLocked(sess *session, state SessionState, errText string) {
	s.mu.Lock()
	delete(s.sessions, sess.id)
	s.recordLocked(sess, state, errText)
	s.mu.Unlock()
	sess.discardLocked()
}

// commitCannotSucceed reports a commit failure that resending the last chunk
// would only repeat: the name is taken and overwrite was not asked for, the
// destination escapes its root, or the namespace can never hold the file.
// Everything else is treated as transient.
func commitCannotSucceed(err error) bool {
	return errors.Is(err, vfs.ErrConflict) ||
		errors.Is(err, vfs.ErrPermissionDenied) ||
		errors.Is(err, vfs.ErrTooLarge)
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

// liveState is what a session in the store is doing right now.
func (sess *session) liveState() SessionState {
	if sess.committing.Load() {
		return SessionCommitting
	}
	return SessionUploading
}

// summary describes the session for ListSessions without taking its lock.
func (sess *session) summary(state SessionState, updatedAt time.Time, errText string) SessionSummary {
	return SessionSummary{
		SessionID: sess.id,
		FileName:  sess.fileName,
		RootDir:   sess.rootDir,
		Serial:    sess.serial,
		TotalSize: sess.totalSize,
		Offset:    sess.committed.Load(),
		State:     state,
		CreatedAt: sess.createdAt,
		UpdatedAt: updatedAt,
		Error:     errText,
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

// orBackground is the context to check a name with when the caller gave none.
func orBackground(ctx context.Context) context.Context {
	if ctx == nil {
		return context.Background()
	}
	return ctx
}
