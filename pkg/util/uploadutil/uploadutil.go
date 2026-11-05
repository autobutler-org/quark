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

	"github.com/autobutler-org/quark/internal/db"
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

	// MaxSessionsPerUser is how many sessions one account may hold open at
	// once (#2756). Each holds an open file and its staged bytes until it
	// commits, is deleted or expires. The app uploads 4 files at a time, so
	// this leaves room for several devices and abandoned sessions.
	MaxSessionsPerUser = 32

	// MaxSessions is how many sessions the process holds open at once,
	// across every account, which bounds the open files they cost.
	MaxSessions = 256
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

	// ErrTooManySessions refuses a session past MaxSessionsPerUser or
	// MaxSessions. The client finishes or cancels one first, or waits for an
	// abandoned one to expire.
	ErrTooManySessions = errors.New("uploadutil: too many upload sessions open")

	// ErrNoDestination means there is nowhere for the finished file to land, so
	// there is no point collecting bytes for it.
	ErrNoDestination = errors.New("uploadutil: no writable upload destination")

	// ErrInvalidBody marks a multipart body that could not be read to its
	// end: cut off, or not multipart at all. The files before the break have
	// landed; the client has to resend the rest.
	ErrInvalidBody = errors.New("uploadutil: malformed multipart body")

	// ErrNoFiles marks a multipart body that saved nothing: no part named
	// "files", or every such part lacked a file name. A thumbnail or any
	// other part does not count. The text is the 400 POST /files/upload
	// returns.
	ErrNoFiles = errors.New("no files in upload; send each file as a multipart part named files")
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

// Destination is where an upload lands: the files namespace of the device it
// names, looked up in the registry, plus the bus that announces the arrival.
// The multipart endpoint and a chunked session both write through it, so every
// upload to every device has one writer, [vfs.VFS.Write] or
// [vfs.FileMover.MoveFileIn] (#2643).
type Destination struct {
	Registry vfs.Registry
	EventBus *eventbus.Bus
}

// UploadedFile is one file an upload wrote.
type UploadedFile struct {
	// Path is where the file landed, files-relative, after any file_(1) rename.
	Path string
	// Created is false when the upload replaced a file that was already there.
	Created bool
	// SourceName is the file name the client sent, before any rename. A
	// sidecar part names its file by it.
	SourceName string
}

// SidecarFunc receives a part of a multipart upload that is not a file, with
// the files written so far, while the part can still be read. A client
// sends a file's thumbnail and preview this way (#2379), right after the file.
type SidecarFunc func(part *multipart.Part, written []UploadedFile)

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
	// KeepBoth lands a file whose name is taken under the first free
	// storageutil.NumberedName. With neither it nor Overwrite, a taken name is
	// vfs.ErrConflict (#2016).
	KeepBoth bool
	// BeforeOverwrite, when set, is called with the file's path just before
	// the write replaces it, while the old content is still there to snapshot.
	BeforeOverwrite func(path string)
}

// WriteFileResult reports where the file ended up, API-relative.
type WriteFileResult struct {
	Path string
	// Created is false when the write replaced a file that was already there.
	Created bool
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
	// KeepBoth lands a part whose name is taken under a free numbered name.
	KeepBoth bool
	// Sidecar, when set, is handed every part that is not a file.
	Sidecar SidecarFunc
	// BeforeOverwrite, when set, is called with a file's path just before a
	// part replaces it, while the old content is still there to snapshot.
	BeforeOverwrite func(path string)
}

// WriteMultipartResult lists the files a multipart body wrote, in the order
// they arrived. When the write fails partway it still lists the files that
// landed before the failure.
type WriteMultipartResult struct {
	Written []UploadedFile
}

// Sidecars attaches the thumbnail parts of a multipart upload to the files
// they belong to (#2379). A client sends each one right after its file, as a
// part named "thumbnail" whose filename is the file's own. Pass its Attach as
// the writer's Sidecar.
type Sidecars struct {
	// Database stores a photo's hashes for duplicate detection. Nil skips
	// them.
	Database *db.DatabaseSqlc
	// FS is the namespace the files are written into, read back for a
	// photo's content hash. Nil stores only the perceptual hash.
	FS vfs.VFS
	// Serial is the device the upload goes to, empty for the internal one.
	Serial string
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
	// finished holds each account's ended sessions, oldest first, at most
	// MaxFinishedSessionsPerUser of them. Guarded by mu.
	finished map[int64][]SessionSummary

	// stagingMu guards prepared: the staging dirs this store has cleared of
	// what an earlier process stranded. It is held across the clear, so no
	// session stages in a dir until the clear is done.
	stagingMu sync.Mutex
	prepared  map[string]bool

	// stagingDir is the internal drive's. A USB drive's sessions stage on the
	// drive itself, beside its files (#3970).
	stagingDir string
	ttl        time.Duration
	now        func() time.Time
}

// NewSessionStoreParams configures a store. Both fields have production
// defaults so tests can pin a temp dir and a short TTL without the rest of the
// codebase caring.
type NewSessionStoreParams struct {
	// StagingDir is where partial uploads to the internal drive are staged.
	// Empty means the data dir's tmp area. An upload to a USB drive stages on
	// that drive whatever this says.
	StagingDir string
	// TTL overrides DefaultSessionTTL. Zero means the default.
	TTL time.Duration
	// Now is the clock sessions expire by. Nil means time.Now.
	Now func() time.Time
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
	now := params.Now
	if now == nil {
		now = time.Now
	}
	return &SessionStore{
		sessions:   make(map[string]*session),
		finished:   make(map[int64][]SessionSummary),
		prepared:   make(map[string]bool),
		stagingDir: stagingDir,
		ttl:        ttl,
		now:        now,
	}
}

// CreateSessionParams opens a session for one file.
type CreateSessionParams struct {
	// Ctx bounds the check for a name already in use and the lookup of where
	// to stage. Nil means background.
	Ctx         context.Context
	Destination Destination
	RootDir     string
	FileName    string
	TotalSize   int64
	Serial      string
	Overwrite   bool
	// KeepBoth commits under a free numbered name if the name is taken.
	// Setting it with Overwrite is ErrInvalidRequest; setting neither makes a
	// taken name vfs.ErrConflict, at creation as well as at commit.
	KeepBoth bool
	// UserID is who opened the session. Every later call on it has to come
	// from the same user; anyone else is told it does not exist (#1903).
	UserID int64
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
	UserID      int64
	Range       ContentRange
	// Body carries exactly Range.Length() bytes. Anything else is a 400.
	Body io.Reader
	// BeforeOverwrite, when set, is called with the finished file's path just
	// before the commit replaces a file on the internal device, while the old
	// content is still there to snapshot. A session for a device addressed by
	// serial never calls it: version history lives on the internal device.
	BeforeOverwrite func(path string)
}

// WriteChunkResult is the committed offset after the chunk, and — once the last
// byte lands — where the finished file went.
type WriteChunkResult struct {
	SessionID string
	Offset    int64
	Complete  bool
	Path      string
	// Serial is the device the finished file went to.
	Serial string
	// Created is false when the finished file replaced one already there.
	Created bool
	// ProgressDue is true when this chunk is the first to land at least
	// ProgressInterval after the last one that was. The caller publishes a
	// progress hint then, so a fast upload does not flood the event stream.
	ProgressDue bool
}

// DescribeSessionParams asks what a session has committed.
type DescribeSessionParams struct {
	SessionID string
	UserID    int64
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
	UserID    int64
}

// DeleteSessionResult is empty; the call either found the session or did not.
type DeleteSessionResult struct{}

// SweepResult reports what a sweep reclaimed.
type SweepResult struct {
	Expired int
}

// SessionState is where an upload session is, as ListSessions reports it.
type SessionState string

const (
	// SessionUploading is a session still taking chunks.
	SessionUploading SessionState = "uploading"
	// SessionCommitting is a session whose last byte has landed and whose file
	// is being flushed and moved into place, which on a slow disk can take
	// minutes.
	SessionCommitting SessionState = "committing"
	// SessionCompleted is a session whose file landed.
	SessionCompleted SessionState = "completed"
	// SessionFailed is a session whose file can never land: its name was taken,
	// or the destination refused it.
	SessionFailed SessionState = "failed"
	// SessionCanceled is a session its owner deleted.
	SessionCanceled SessionState = "canceled"
	// SessionExpired is a session that sat idle past its TTL.
	SessionExpired SessionState = "expired"
)

const (
	// ProgressInterval is the least time between two chunks that report
	// ProgressDue for one session.
	ProgressInterval = 2 * time.Second
	// MaxFinishedSessionsPerUser is how many ended sessions ListSessions keeps
	// for each account, newest first, so an upload that ends between two
	// polls still shows how it ended.
	MaxFinishedSessionsPerUser = 50
	// FinishedSessionMaxAge is how long an ended session stays listed.
	FinishedSessionMaxAge = 24 * time.Hour
)

// SessionSummary is one upload session as ListSessions reports it. It carries
// no file content and nothing the session's owner did not send.
type SessionSummary struct {
	SessionID string
	FileName  string
	RootDir   string
	// Serial is the device the file is going to. Empty is the internal drive.
	Serial    string
	TotalSize int64
	// Offset is how many bytes have been committed.
	Offset    int64
	State     SessionState
	CreatedAt time.Time
	// UpdatedAt is when the last chunk landed, or when the session ended.
	UpdatedAt time.Time
	// Error is diagnostic text for a failed session, not copy for a user.
	Error string
}

// ListSessionsParams names whose sessions to list. Only a session's owner sees
// it, the same as every other call on it.
type ListSessionsParams struct {
	UserID int64
}

// ListSessionsResult is the caller's sessions: those in flight, oldest first,
// then those that ended, newest first.
type ListSessionsResult struct {
	Active   []SessionSummary
	Finished []SessionSummary
}
