// Package uploadutil owns the server side of file uploads: where a finished
// upload lands, and the resumable chunked sessions that feed it (#1629).
package uploadutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const (
	// DefaultSessionTTL is how long an idle session survives before the sweeper
	// takes its bytes back. A multi-gigabyte upload over a bad link can take
	// hours, and a browser tab that is closed and reopened the next morning
	// should still be able to resume, so the window is generous — the cost of
	// getting it wrong is a restarted upload, not lost data.
	DefaultSessionTTL = 24 * time.Hour

	// DefaultSweepInterval is how often StartSweeper looks for expired sessions.
	DefaultSweepInterval = time.Hour
)

// contentRangeUnit is the only unit the chunk endpoint accepts. RFC 7233 allows
// others; nothing sends them.
const contentRangeUnit = "bytes "

var (
	// ErrSessionNotFound covers unknown, completed and expired sessions alike.
	// The client's only recourse is a new session from byte zero, and telling
	// the three apart would leak how long a stranger's upload has been running.
	ErrSessionNotFound = errors.New("uploadutil: upload session not found")

	// ErrInvalidRange marks a chunk the server cannot place: a malformed
	// Content-Range, a total that contradicts the session, or a body whose
	// length disagrees with the range it claims to carry.
	ErrInvalidRange = errors.New("uploadutil: invalid content range")

	// ErrInvalidRequest marks a session that cannot be opened as described.
	ErrInvalidRequest = errors.New("uploadutil: invalid upload session request")

	// ErrNoDestination means there is nowhere for the finished file to land, so
	// there is no point collecting bytes for it.
	ErrNoDestination = errors.New("uploadutil: no writable upload destination")
)

// ContentRange is a parsed Content-Range request header: `bytes 0-262143/1000000`.
// End is inclusive, matching the header and Google's resumable upload protocol,
// so a chunk carries End-Start+1 bytes.
type ContentRange struct {
	Start int64
	End   int64
	Total int64
}

// Length is the number of bytes the chunk body must carry.
func (r ContentRange) Length() int64 {
	return r.End - r.Start + 1
}

// ParseContentRange reads the header a chunk PUT must carry. Every failure
// wraps ErrInvalidRange, which the HTTP layer turns into a 400: a client that
// cannot state which bytes it is sending has nothing the server can commit.
//
// The `bytes */SIZE` form RFC 7233 allows for asking what the server has is
// deliberately rejected — that question is GET on the session, which answers
// with the offset in the body rather than in a header.
func ParseContentRange(header string) (ContentRange, error) {
	trimmed := strings.TrimSpace(header)
	if trimmed == "" {
		return ContentRange{}, fmt.Errorf("%w: missing Content-Range header", ErrInvalidRange)
	}
	if !strings.HasPrefix(trimmed, contentRangeUnit) {
		return ContentRange{}, fmt.Errorf("%w: %q is not a byte range", ErrInvalidRange, header)
	}

	spec := strings.TrimSpace(strings.TrimPrefix(trimmed, contentRangeUnit))
	rangePart, totalPart, ok := strings.Cut(spec, "/")
	if !ok {
		return ContentRange{}, fmt.Errorf("%w: %q has no total size", ErrInvalidRange, header)
	}
	startPart, endPart, ok := strings.Cut(rangePart, "-")
	if !ok {
		return ContentRange{}, fmt.Errorf("%w: %q has no byte range", ErrInvalidRange, header)
	}

	start, err := strconv.ParseInt(startPart, 10, 64)
	if err != nil {
		return ContentRange{}, fmt.Errorf("%w: bad range start in %q", ErrInvalidRange, header)
	}
	end, err := strconv.ParseInt(endPart, 10, 64)
	if err != nil {
		return ContentRange{}, fmt.Errorf("%w: bad range end in %q", ErrInvalidRange, header)
	}
	total, err := strconv.ParseInt(totalPart, 10, 64)
	if err != nil {
		return ContentRange{}, fmt.Errorf("%w: bad total size in %q", ErrInvalidRange, header)
	}

	parsed := ContentRange{Start: start, End: end, Total: total}
	if start < 0 || end < start || total <= 0 || end >= total {
		return ContentRange{}, fmt.Errorf("%w: %q is not a satisfiable range", ErrInvalidRange, header)
	}
	return parsed, nil
}

// Destination is the pair of writers an upload can land in, plus the bus that
// announces the arrival. Both the multipart endpoint and a chunked session
// choose between the two the same way, which is the whole point of holding the
// choice in one place.
type Destination struct {
	Registry vfs.Registry
	Storage  *storageutil.StorageService
	EventBus *eventbus.Bus
}

// WriteFileParams is one finished file on its way into the namespace.
type WriteFileParams struct {
	Ctx context.Context
	// Reader is positioned at the first byte of the file and read to EOF.
	Reader io.Reader
	// SourcePath, when set, is the host file Reader reads. A namespace that can
	// take the file by rename ([vfs.FileMover]) moves it instead of copying it,
	// and the file is gone afterwards; any other destination reads Reader.
	SourcePath string
	RootDir    string
	FileName   string
	Serial     string
	Overwrite  bool
}

// WriteFileResult reports where the file ended up, API-relative.
type WriteFileResult struct {
	Path string
}

// WriteMultipartParams is a whole multipart body on its way into the
// namespace: however many files the client attached, streamed part by part
// rather than buffered.
type WriteMultipartParams struct {
	Ctx context.Context
	// FS is the namespace the parts are written into.
	FS vfs.VFS
	// Reader is the request's multipart body, read to its last part.
	Reader *multipart.Reader
	// RootDir is the directory the files land in; it is created if missing.
	RootDir string
	// Overwrite lets a part replace a file that is already there.
	Overwrite bool
}

// OffsetMismatchError is the resync signal. The client asked to append at a
// byte the server is not sitting on, which is what happens when a response was
// lost in flight or a chunk failed halfway; the committed offset travels with
// the error so the HTTP layer can hand it back in one round trip instead of
// making the client ask.
type OffsetMismatchError struct {
	Start  int64
	Offset int64
}

func (e *OffsetMismatchError) Error() string {
	return fmt.Sprintf("chunk starts at %d but %d bytes are committed", e.Start, e.Offset)
}

// SessionStore holds the in-flight resumable uploads. Sessions live in memory
// only: a restart drops them, the client sees a 404 on its next chunk and
// starts the file over. Persisting them would mean reconciling the map with
// the staged files on disk on every boot, for a case that costs one restarted
// upload.
type SessionStore struct {
	// mu guards sessions. It is never held while a session's own lock is taken
	// — Sweep and Close collect first and clean up after releasing it — so a
	// long chunk write cannot block session lookups on unrelated uploads.
	mu       sync.Mutex
	sessions map[string]*session

	stagingDir string
	ttl        time.Duration
}

// NewSessionStoreParams configures a store. Both fields have production
// defaults so tests can pin a temp dir and a short TTL without the rest of the
// codebase caring.
type NewSessionStoreParams struct {
	// StagingDir is where partial uploads are staged. Empty means the data
	// dir's tmp area.
	StagingDir string
	// TTL overrides DefaultSessionTTL. Zero means the default.
	TTL time.Duration
}

// NewSessionStore builds an empty store. It starts no goroutine and touches no
// disk — every dependency graph in the process builds one of these, including
// the ones in tests that never upload anything. Call StartSweeper once, from
// server startup, to give it a heartbeat.
func NewSessionStore(params NewSessionStoreParams) *SessionStore {
	stagingDir := params.StagingDir
	if stagingDir == "" {
		stagingDir = filepath.Join(storageutil.GetDataDir(), "tmp", stagingDirName)
	}
	ttl := params.TTL
	if ttl <= 0 {
		ttl = DefaultSessionTTL
	}
	return &SessionStore{
		sessions:   make(map[string]*session),
		stagingDir: stagingDir,
		ttl:        ttl,
	}
}

// CreateSessionParams opens a session for one file.
type CreateSessionParams struct {
	Destination Destination
	RootDir     string
	FileName    string
	TotalSize   int64
	Serial      string
	Overwrite   bool
}

// CreateSessionResult is what the client needs to start sending.
type CreateSessionResult struct {
	SessionID string
	Offset    int64
	ExpiresAt time.Time
}

// WriteChunkParams is one chunk PUT.
type WriteChunkParams struct {
	Ctx         context.Context
	Destination Destination
	SessionID   string
	Range       ContentRange
	// Body carries exactly Range.Length() bytes. Anything else is a 400.
	Body io.Reader
}

// WriteChunkResult is the committed offset after the chunk, and — once the last
// byte lands — where the finished file went.
type WriteChunkResult struct {
	SessionID string
	Offset    int64
	Complete  bool
	Path      string
}

// DescribeSessionParams asks what a session has committed.
type DescribeSessionParams struct {
	SessionID string
}

// DescribeSessionResult is everything a resuming client needs to pick up where
// it left off.
type DescribeSessionResult struct {
	SessionID string
	Offset    int64
	TotalSize int64
	FileName  string
	RootDir   string
	ExpiresAt time.Time
}

// DeleteSessionParams abandons a session.
type DeleteSessionParams struct {
	SessionID string
}

// DeleteSessionResult is empty; the call either found the session or did not.
type DeleteSessionResult struct{}

// SweepResult reports what a sweep reclaimed.
type SweepResult struct {
	Expired int
}
