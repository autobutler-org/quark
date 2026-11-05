package uploadutil_test

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// The store is tested here without an HTTP context on purpose: the offset
// arithmetic, the staging file's lifetime and the locking are what a chunked
// upload's correctness rests on, and none of them need a request to exercise
// (#1629). The endpoint's own behavior is pinned in
// internal/server/api/v0/files/upload_session_test.go.

func newTestStore(t *testing.T) *uploadutil.SessionStore {
	t.Helper()
	store := uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{
		StagingDir: filepath.Join(t.TempDir(), "upload-sessions"),
	})
	t.Cleanup(func() {
		if err := store.Close(); err != nil {
			t.Errorf("close store: %v", err)
		}
	})
	return store
}

func newTestDestination(t *testing.T) (uploadutil.Destination, vfs.VFS) {
	t.Helper()
	fsys := vfs.NewMemVFS("files")
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, fsys); err != nil {
		t.Fatalf("register files namespace: %v", err)
	}
	return uploadutil.Destination{Registry: registry, EventBus: eventbus.New()}, fsys
}

func openSession(t *testing.T, store *uploadutil.SessionStore, dest uploadutil.Destination, name string, size int64) string {
	t.Helper()
	result, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest,
		FileName:    name,
		TotalSize:   size,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	return result.SessionID
}

func writeChunk(
	store *uploadutil.SessionStore,
	dest uploadutil.Destination,
	sessionID string,
	start, end, total int64,
	body []byte,
) (uploadutil.WriteChunkResult, error) {
	return store.WriteChunk(uploadutil.WriteChunkParams{
		Ctx:         context.Background(),
		Destination: dest,
		SessionID:   sessionID,
		Range:       uploadutil.ContentRange{Start: start, End: end, Total: total},
		Body:        bytes.NewReader(body),
	})
}

// A session belongs to the user who opened it (#1903). To anyone else it does
// not exist, on every verb, and their attempt leaves it untouched for its owner.
func TestSessionBelongsToItsOpener(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	const owner, stranger = int64(7), int64(8)
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest, FileName: "mine.bin", TotalSize: 4, UserID: owner,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	id := created.SessionID

	if _, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: id, UserID: stranger}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("a stranger described the session: %v", err)
	}
	if _, err := store.WriteChunk(uploadutil.WriteChunkParams{
		Ctx: context.Background(), Destination: dest, SessionID: id, UserID: stranger,
		Range: uploadutil.ContentRange{Start: 0, End: 3, Total: 4}, Body: bytes.NewReader([]byte("abcd")),
	}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("a stranger wrote to the session: %v", err)
	}
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: id, UserID: stranger}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("a stranger deleted the session: %v", err)
	}

	described, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: id, UserID: owner})
	if err != nil || described.Offset != 0 {
		t.Fatalf("the owner lost the session: %+v, %v", described, err)
	}
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: id, UserID: owner}); err != nil {
		t.Errorf("the owner could not delete the session: %v", err)
	}
}

// The access layer grants ownership only on a file an upload created, so a
// commit has to say whether it replaced one (#1903).
func TestCommitReportsWhetherTheFileIsNew(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	if err := os.WriteFile(filepath.Join(root, "taken.txt"), []byte("old"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}
	content := []byte("data")
	total := int64(len(content))

	for _, tc := range []struct {
		name      string
		overwrite bool
		created   bool
	}{
		{name: "new.txt", created: true},
		{name: "taken.txt", overwrite: true, created: false},
	} {
		opened, err := store.CreateSession(uploadutil.CreateSessionParams{
			Destination: dest, FileName: tc.name, TotalSize: total, Overwrite: tc.overwrite,
		})
		if err != nil {
			t.Fatalf("create session for %s: %v", tc.name, err)
		}
		result, err := writeChunk(store, dest, opened.SessionID, 0, total-1, total, content)
		if err != nil {
			t.Fatalf("commit %s: %v", tc.name, err)
		}
		if !result.Complete || result.Path != tc.name || result.Created != tc.created {
			t.Errorf("commit %s = %+v, want path %q created=%v", tc.name, result, tc.name, tc.created)
		}
	}
}

func TestParseContentRange(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name   string
		header string
		want   uploadutil.ContentRange
		wantOK bool
	}{
		{
			name:   "a whole small file",
			header: "bytes 0-15/16",
			want:   uploadutil.ContentRange{Start: 0, End: 15, Total: 16},
			wantOK: true,
		},
		{
			name:   "a chunk in the middle",
			header: "bytes 8388608-16777215/20971520",
			want:   uploadutil.ContentRange{Start: 8388608, End: 16777215, Total: 20971520},
			wantOK: true,
		},
		{name: "empty", header: ""},
		{name: "only whitespace", header: "   "},
		{name: "another unit", header: "chunks 0-15/16"},
		{name: "no total", header: "bytes 0-15"},
		{name: "no range", header: "bytes 15/16"},
		{name: "unparseable start", header: "bytes x-15/16"},
		{name: "unparseable end", header: "bytes 0-x/16"},
		{name: "unparseable total", header: "bytes 0-15/x"},
		{name: "negative start", header: "bytes -1-15/16"},
		{name: "end before start", header: "bytes 15-0/16"},
		{name: "end past the total", header: "bytes 0-16/16"},
		{name: "zero total", header: "bytes 0-0/0"},
		// RFC 7233 allows this to ask what the server holds; that question is
		// GET on the session here, so the chunk endpoint refuses it.
		{name: "the unknown-range form", header: "bytes */16"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := uploadutil.ParseContentRange(tc.header)
			if tc.wantOK {
				if err != nil {
					t.Fatalf("ParseContentRange(%q) failed: %v", tc.header, err)
				}
				if got != tc.want {
					t.Errorf("ParseContentRange(%q) = %+v, want %+v", tc.header, got, tc.want)
				}
				if want := tc.want.End - tc.want.Start + 1; got.Length() != want {
					t.Errorf("Length() = %d, want %d", got.Length(), want)
				}
				return
			}
			if !errors.Is(err, uploadutil.ErrInvalidRange) {
				t.Errorf("ParseContentRange(%q) = %+v, %v; want ErrInvalidRange", tc.header, got, err)
			}
		})
	}
}

func TestCreateSessionRejectsAnUndescribableFile(t *testing.T) {
	t.Parallel()

	dest, _ := newTestDestination(t)

	cases := []struct {
		name    string
		params  uploadutil.CreateSessionParams
		wantErr error
	}{
		{
			name:    "no file name",
			params:  uploadutil.CreateSessionParams{FileName: "", TotalSize: 16},
			wantErr: uploadutil.ErrInvalidRequest,
		},
		{
			name:    "file name is a separator",
			params:  uploadutil.CreateSessionParams{FileName: "/", TotalSize: 16},
			wantErr: uploadutil.ErrInvalidRequest,
		},
		{
			name:    "zero total size",
			params:  uploadutil.CreateSessionParams{FileName: "empty.bin", TotalSize: 0},
			wantErr: uploadutil.ErrInvalidRequest,
		},
		{
			name:    "negative total size",
			params:  uploadutil.CreateSessionParams{FileName: "odd.bin", TotalSize: -1},
			wantErr: uploadutil.ErrInvalidRequest,
		},
		{
			name:    "rootDir climbs out of the upload root",
			params:  uploadutil.CreateSessionParams{RootDir: "../../escape", FileName: "loot.txt", TotalSize: 16},
			wantErr: uploadutil.ErrInvalidRequest,
		},
		{
			name:    "rootDir is only a traversal",
			params:  uploadutil.CreateSessionParams{RootDir: "..", FileName: "loot.txt", TotalSize: 16},
			wantErr: uploadutil.ErrInvalidRequest,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			store := newTestStore(t)
			params := tc.params
			params.Destination = dest
			if _, err := store.CreateSession(params); !errors.Is(err, tc.wantErr) {
				t.Errorf("CreateSession(%+v) = %v, want %v", params, err, tc.wantErr)
			}
			// A refused session stages nothing.
			if _, err := os.Stat(store.StagingDir()); err == nil {
				entries, readErr := os.ReadDir(store.StagingDir())
				if readErr == nil && len(entries) > 0 {
					t.Errorf("a refused session staged %d file(s)", len(entries))
				}
			}
		})
	}
}

// Structure travels in rootDir; the filename is flattened to its basename
// (#1603). Both are settled at session creation, before any byte is staged.
func TestCreateSessionNormalizesThePath(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name         string
		rootDir      string
		fileName     string
		wantRootDir  string
		wantFileName string
	}{
		{name: "a flat name at the root", fileName: "clip.mp4", wantFileName: "clip.mp4"},
		{
			name:         "a nested name is flattened",
			fileName:     "notes/meeting.txt",
			wantFileName: "meeting.txt",
		},
		{
			name:         "a traversing name is flattened",
			fileName:     "../../escape.txt",
			wantFileName: "escape.txt",
		},
		{
			name:         "rootDir carries the structure",
			rootDir:      "photos/2024",
			fileName:     "img.jpg",
			wantRootDir:  "photos/2024",
			wantFileName: "img.jpg",
		},
		{
			name:         "a leading slash is not an absolute path",
			rootDir:      "/photos/2024/",
			fileName:     "img.jpg",
			wantRootDir:  "photos/2024",
			wantFileName: "img.jpg",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			store := newTestStore(t)
			dest, _ := newTestDestination(t)

			created, err := store.CreateSession(uploadutil.CreateSessionParams{
				Destination: dest,
				RootDir:     tc.rootDir,
				FileName:    tc.fileName,
				TotalSize:   16,
			})
			if err != nil {
				t.Fatalf("create session: %v", err)
			}

			described, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: created.SessionID})
			if err != nil {
				t.Fatalf("describe session: %v", err)
			}
			if described.RootDir != tc.wantRootDir {
				t.Errorf("rootDir = %q, want %q", described.RootDir, tc.wantRootDir)
			}
			if described.FileName != tc.wantFileName {
				t.Errorf("fileName = %q, want %q", described.FileName, tc.wantFileName)
			}
		})
	}
}

// A session with nowhere to put the finished file is not worth opening.
func TestCreateSessionNeedsAWritableDestination(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	_, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: uploadutil.Destination{},
		FileName:    "nowhere.bin",
		TotalSize:   16,
	})
	if !errors.Is(err, uploadutil.ErrNoDestination) {
		t.Fatalf("CreateSession with no destination = %v, want ErrNoDestination", err)
	}
}

// Session ids are the only thing keeping one caller from appending to another
// caller's upload, so they have to be unguessable rather than merely unique.
func TestSessionIDsAreRandom(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)

	const sessions = 32
	seen := make(map[string]bool, sessions)
	for range sessions {
		id := openSession(t, store, dest, "clip.mp4", 1024)
		if seen[id] {
			t.Fatalf("session id %q was handed out twice", id)
		}
		if len(id) != 32 {
			t.Fatalf("session id %q is %d characters, want 32 hex characters", id, len(id))
		}
		seen[id] = true
	}
}

func TestWriteChunkAppendsAndCommits(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, fsys := newTestDestination(t)

	content := []byte("one two three four five six seven")
	total := int64(len(content))
	id := openSession(t, store, dest, "words.txt", total)

	const half = 16
	first, err := writeChunk(store, dest, id, 0, half-1, total, content[:half])
	if err != nil {
		t.Fatalf("first chunk: %v", err)
	}
	if first.Offset != half || first.Complete {
		t.Fatalf("first chunk returned %+v, want offset %d and complete=false", first, half)
	}

	last, err := writeChunk(store, dest, id, half, total-1, total, content[half:])
	if err != nil {
		t.Fatalf("last chunk: %v", err)
	}
	if !last.Complete || last.Offset != total {
		t.Fatalf("last chunk returned %+v, want offset %d and complete=true", last, total)
	}
	if last.Path != "words.txt" {
		t.Errorf("committed path is %q, want %q", last.Path, "words.txt")
	}

	stored, err := fsys.Open(context.Background(), "words.txt")
	if err != nil {
		t.Fatalf("open the committed file: %v", err)
	}
	defer stored.Close()
	got, err := io.ReadAll(stored)
	if err != nil {
		t.Fatalf("read the committed file: %v", err)
	}
	if !bytes.Equal(got, content) {
		t.Errorf("committed file is %q, want %q", got, content)
	}

	// The session is gone the moment the file lands.
	if _, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: id}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("a completed session is still described: %v", err)
	}
}

func TestWriteChunkOffsetSemantics(t *testing.T) {
	t.Parallel()

	const total = int64(64)
	committed := bytes.Repeat([]byte("a"), 16)

	cases := []struct {
		name       string
		start, end int64
		body       []byte
		wantOffset int64
		wantErr    error
		// declaredTotal overrides the total the chunk claims; zero means the
		// session's own totalSize.
		declaredTotal int64
		// wantMismatch, when set, is the offset a conflict must report.
		wantMismatch int64
		conflict     bool
	}{
		{
			name: "the next chunk in sequence", start: 16, end: 31,
			body: bytes.Repeat([]byte("b"), 16), wantOffset: 32,
		},
		{
			name: "a replay entirely below the offset", start: 0, end: 15,
			body: committed, wantOffset: 16,
		},
		{
			name: "a chunk straddling the offset", start: 0, end: 31,
			body: bytes.Repeat([]byte("b"), 32), conflict: true, wantMismatch: 16,
		},
		{
			name: "a gap past the offset", start: 32, end: 47,
			body: bytes.Repeat([]byte("b"), 16), conflict: true, wantMismatch: 16,
		},
		{
			name: "a body shorter than its range", start: 16, end: 31,
			body: bytes.Repeat([]byte("b"), 8), wantErr: uploadutil.ErrInvalidRange, wantOffset: 16,
		},
		{
			name: "a body longer than its range", start: 16, end: 31,
			body: bytes.Repeat([]byte("b"), 24), wantErr: uploadutil.ErrInvalidRange, wantOffset: 16,
		},
		{
			name: "a total contradicting the session", start: 16, end: 31,
			body: bytes.Repeat([]byte("b"), 16), declaredTotal: total * 2,
			wantErr: uploadutil.ErrInvalidRange, wantOffset: 16,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			store := newTestStore(t)
			dest, _ := newTestDestination(t)
			id := openSession(t, store, dest, "partial.bin", total)

			if _, err := writeChunk(store, dest, id, 0, 15, total, committed); err != nil {
				t.Fatalf("staging the committed bytes: %v", err)
			}

			declaredTotal := tc.declaredTotal
			if declaredTotal == 0 {
				declaredTotal = total
			}
			result, err := writeChunk(store, dest, id, tc.start, tc.end, declaredTotal, tc.body)

			switch {
			case tc.conflict:
				var mismatch *uploadutil.OffsetMismatchError
				if !errors.As(err, &mismatch) {
					t.Fatalf("got %+v, %v; want an OffsetMismatchError", result, err)
				}
				if mismatch.Offset != tc.wantMismatch {
					t.Errorf("conflict reports offset %d, want %d", mismatch.Offset, tc.wantMismatch)
				}
			case tc.wantErr != nil:
				if !errors.Is(err, tc.wantErr) {
					t.Fatalf("got %+v, %v; want %v", result, err, tc.wantErr)
				}
			default:
				if err != nil {
					t.Fatalf("write chunk: %v", err)
				}
				if result.Offset != tc.wantOffset {
					t.Errorf("offset = %d, want %d", result.Offset, tc.wantOffset)
				}
			}

			// Whatever happened, the session's own idea of the offset has to
			// match what the next chunk will be judged against.
			described, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: id})
			if err != nil {
				t.Fatalf("describe session: %v", err)
			}
			want := tc.wantOffset
			if tc.conflict {
				want = tc.wantMismatch
			}
			if described.Offset != want {
				t.Errorf("session offset is %d, want %d", described.Offset, want)
			}
		})
	}
}

// A rejected chunk must leave nothing of itself behind, or the next chunk lands
// on top of half-written bytes and the file is silently wrong.
func TestARejectedChunkLeavesTheStagedFileIntact(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, fsys := newTestDestination(t)

	content := bytes.Repeat([]byte("abcdefgh"), 8)
	total := int64(len(content))
	id := openSession(t, store, dest, "recovered.bin", total)

	if _, err := writeChunk(store, dest, id, 0, 31, total, content[:32]); err != nil {
		t.Fatalf("first chunk: %v", err)
	}
	// Claims 32 bytes, carries 8.
	if _, err := writeChunk(store, dest, id, 32, 63, total, content[32:40]); !errors.Is(err, uploadutil.ErrInvalidRange) {
		t.Fatalf("a short chunk returned %v, want ErrInvalidRange", err)
	}
	// The client retries the same range in full and the file comes out whole.
	result, err := writeChunk(store, dest, id, 32, 63, total, content[32:])
	if err != nil {
		t.Fatalf("retried chunk: %v", err)
	}
	if !result.Complete {
		t.Fatalf("retried chunk returned %+v, want complete=true", result)
	}

	stored, err := fsys.Open(context.Background(), "recovered.bin")
	if err != nil {
		t.Fatalf("open the committed file: %v", err)
	}
	defer stored.Close()
	got, err := io.ReadAll(stored)
	if err != nil {
		t.Fatalf("read the committed file: %v", err)
	}
	if !bytes.Equal(got, content) {
		t.Errorf("committed file is %q, want %q", got, content)
	}
}

// Chunks for one file arrive on separate connections and can overlap in time.
// Only one of them can be at the committed offset; the loser has to be turned
// away rather than interleaved into the staged file.
func TestConcurrentChunksDoNotInterleave(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, fsys := newTestDestination(t)

	const chunk = 4096
	first := bytes.Repeat([]byte("1"), chunk)
	second := bytes.Repeat([]byte("2"), chunk)
	total := int64(2 * chunk)
	id := openSession(t, store, dest, "raced.bin", total)

	const racers = 8
	var wg sync.WaitGroup
	accepted := make([]bool, racers)
	for i := range racers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			// Every racer offers the same first chunk. Exactly one can win; the
			// rest are either replays (200, nothing written) or conflicts.
			result, err := writeChunk(store, dest, id, 0, chunk-1, total, first)
			accepted[i] = err == nil && result.Offset == chunk
		}()
	}
	wg.Wait()

	won := 0
	for _, ok := range accepted {
		if ok {
			won++
		}
	}
	if won == 0 {
		t.Fatal("no racer committed the first chunk")
	}

	described, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: id})
	if err != nil {
		t.Fatalf("describe session: %v", err)
	}
	if described.Offset != chunk {
		t.Fatalf("after %d racing writes the offset is %d, want %d", racers, described.Offset, chunk)
	}

	if _, err := writeChunk(store, dest, id, chunk, total-1, total, second); err != nil {
		t.Fatalf("second chunk: %v", err)
	}
	stored, err := fsys.Open(context.Background(), "raced.bin")
	if err != nil {
		t.Fatalf("open the committed file: %v", err)
	}
	defer stored.Close()
	got, err := io.ReadAll(stored)
	if err != nil {
		t.Fatalf("read the committed file: %v", err)
	}
	if want := append(append([]byte{}, first...), second...); !bytes.Equal(got, want) {
		t.Errorf("the committed file is not the two chunks in order (%d bytes)", len(got))
	}
}

func TestUnknownSessionIsNotFound(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	const unknown = "0123456789abcdef0123456789abcdef"

	if _, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: unknown}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("DescribeSession = %v, want ErrSessionNotFound", err)
	}
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: unknown}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("DeleteSession = %v, want ErrSessionNotFound", err)
	}
	if _, err := writeChunk(store, dest, unknown, 0, 15, 16, make([]byte, 16)); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("WriteChunk = %v, want ErrSessionNotFound", err)
	}
}

func TestSweepReclaimsExpiredSessions(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)

	live := openSession(t, store, dest, "live.bin", 1024)
	if _, err := writeChunk(store, dest, live, 0, 511, 1024, make([]byte, 512)); err != nil {
		t.Fatalf("chunk: %v", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 1 {
		t.Fatalf("expected 1 staged file, found %d", got)
	}

	// Nothing has expired yet.
	if result := store.Sweep(time.Now()); result.Expired != 0 {
		t.Fatalf("sweep expired %d sessions before the TTL", result.Expired)
	}
	if result := store.Sweep(time.Now().Add(2 * uploadutil.DefaultSessionTTL)); result.Expired != 1 {
		t.Fatalf("sweep expired %d sessions, want 1", result.Expired)
	}
	if _, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: live}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("a swept session is still described: %v", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("sweep left %d staged file(s) behind", got)
	}
}

// A session past its deadline is unusable the moment it is touched, not only
// once the sweeper's next tick comes round.
func TestAnExpiredSessionIsRefusedBeforeTheSweep(t *testing.T) {
	t.Parallel()

	store := uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{
		StagingDir: filepath.Join(t.TempDir(), "upload-sessions"),
		TTL:        time.Nanosecond,
	})
	t.Cleanup(func() { _ = store.Close() })

	dest, _ := newTestDestination(t)
	id := openSession(t, store, dest, "brief.bin", 1024)

	if _, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: id}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Fatalf("an expired session was described: %v", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("the expired session left %d staged file(s) behind", got)
	}
}

func TestDeleteSessionRemovesTheStagedFile(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)

	id := openSession(t, store, dest, "cancelled.bin", 1024)
	if _, err := writeChunk(store, dest, id, 0, 511, 1024, make([]byte, 512)); err != nil {
		t.Fatalf("chunk: %v", err)
	}
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: id}); err != nil {
		t.Fatalf("delete session: %v", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("delete left %d staged file(s) behind", got)
	}
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: id}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("deleting twice = %v, want ErrSessionNotFound", err)
	}
}

// Cancelling the sweeper's context drops what is still in flight — sessions do
// not survive a restart, so leaving their bytes on disk would only strand them.
func TestStartSweeperDropsEverythingOnShutdown(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	openSession(t, store, dest, "interrupted.bin", 1024)

	ctx, cancel := context.WithCancel(context.Background())
	store.StartSweeper(ctx, time.Hour)
	cancel()

	deadline := time.Now().Add(5 * time.Second)
	for stagedCount(t, store.StagingDir()) > 0 {
		if time.Now().After(deadline) {
			t.Fatal("the sweeper did not drop the staged files after its context was cancelled")
		}
		time.Sleep(time.Millisecond)
	}
}

func stagedCount(t *testing.T, stagingDir string) int {
	t.Helper()
	entries, err := os.ReadDir(stagingDir)
	if os.IsNotExist(err) {
		return 0
	}
	if err != nil {
		t.Fatalf("read staging dir %s: %v", stagingDir, err)
	}
	return len(entries)
}

// newLocalDestination backs the files namespace with a host directory, the
// shape a device has, so a commit can rename rather than copy (#1828).
func newLocalDestination(t *testing.T) (uploadutil.Destination, string) {
	t.Helper()
	root := t.TempDir()
	fsys, err := vfs.NewLocalVFS(root, "files")
	if err != nil {
		t.Fatalf("NewLocalVFS: %v", err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, fsys); err != nil {
		t.Fatalf("register files namespace: %v", err)
	}
	return uploadutil.Destination{Registry: registry, EventBus: eventbus.New()}, root
}

// stagedFile is the one file a single open session has staged.
func stagedFile(t *testing.T, store *uploadutil.SessionStore) string {
	t.Helper()
	matches, err := filepath.Glob(filepath.Join(store.StagingDir(), "*"))
	if err != nil || len(matches) != 1 {
		t.Fatalf("want exactly one staged file, got %v (%v)", matches, err)
	}
	return matches[0]
}

func commitWhole(
	t *testing.T,
	store *uploadutil.SessionStore,
	dest uploadutil.Destination,
	name string,
	overwrite bool,
	content []byte,
) (string, error) {
	t.Helper()
	return commitWholeSeeding(t, store, dest, name, overwrite, content, func() {})
}

// commitWholeSeeding is commitWhole with a hook that runs once the session is
// open, for a destination that only becomes occupied mid-upload.
func commitWholeSeeding(
	t *testing.T,
	store *uploadutil.SessionStore,
	dest uploadutil.Destination,
	name string,
	overwrite bool,
	content []byte,
	afterOpen func(),
) (string, error) {
	t.Helper()
	total := int64(len(content))
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest,
		FileName:    name,
		TotalSize:   total,
		Overwrite:   overwrite,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	afterOpen()
	staged := stagedFile(t, store)
	_, err = writeChunk(store, dest, created.SessionID, 0, total-1, total, content)
	return staged, err
}

func TestCommitRenamesTheStagedFileIntoPlace(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	content := []byte("moved, not copied")
	total := int64(len(content))

	id := openSession(t, store, dest, "big.bin", total)
	before, err := os.Stat(stagedFile(t, store))
	if err != nil {
		t.Fatalf("stat staged file: %v", err)
	}
	if _, err := writeChunk(store, dest, id, 0, total-1, total, content); err != nil {
		t.Fatalf("commit: %v", err)
	}

	after, err := os.Stat(filepath.Join(root, "big.bin"))
	if err != nil {
		t.Fatalf("stat committed file: %v", err)
	}
	if !os.SameFile(before, after) {
		t.Error("the committed file is a copy; the staged file should have been renamed into place")
	}
	if got, _ := os.ReadFile(filepath.Join(root, "big.bin")); !bytes.Equal(got, content) {
		t.Errorf("committed file is %q, want %q", got, content)
	}
	if left, _ := os.ReadDir(store.StagingDir()); len(left) != 0 {
		t.Errorf("staging dir still holds %d entries after the commit", len(left))
	}
}

// A session whose name is already taken is refused when it is opened, before
// a byte is staged (#2016).
func TestOpeningASessionOnATakenNameIsRefused(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	if err := os.WriteFile(filepath.Join(root, "taken.txt"), []byte("original"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}

	_, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest,
		FileName:    "taken.txt",
		TotalSize:   8,
	})
	if !errors.Is(err, vfs.ErrConflict) {
		t.Fatalf("opening a session on a taken name returned %v, want vfs.ErrConflict", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("a refused session staged %d file(s)", got)
	}
}

// Keeping both commits under the first free numbered name rather than over
// the file that is there.
func TestCommitKeepingBothLandsUnderAFreeName(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	if err := os.WriteFile(filepath.Join(root, "taken.txt"), []byte("original"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}

	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest,
		FileName:    "taken.txt",
		TotalSize:   8,
		KeepBoth:    true,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	result, err := writeChunk(store, dest, created.SessionID, 0, 7, 8, []byte("intruder"))
	if err != nil {
		t.Fatalf("commit: %v", err)
	}
	if result.Path != "taken_(1).txt" {
		t.Errorf("commit landed at %q, want %q", result.Path, "taken_(1).txt")
	}
	if got, _ := os.ReadFile(filepath.Join(root, "taken.txt")); string(got) != "original" {
		t.Errorf("the original now reads %q", got)
	}
	if got, _ := os.ReadFile(filepath.Join(root, "taken_(1).txt")); string(got) != "intruder" {
		t.Errorf("the second copy reads %q", got)
	}
}

// The same name taken while the bytes were in flight is caught at the commit,
// which the creation check cannot see.
func TestCommitWithoutOverwriteLeavesAnExistingFileAlone(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	existing := filepath.Join(root, "taken.txt")

	staged, err := commitWholeSeeding(t, store, dest, "taken.txt", false, []byte("intruder"), func() {
		if err := os.WriteFile(existing, []byte("original"), 0o644); err != nil {
			t.Fatalf("seed: %v", err)
		}
	})
	if !errors.Is(err, vfs.ErrConflict) {
		t.Fatalf("commit over an existing file returned %v, want vfs.ErrConflict", err)
	}
	if got, _ := os.ReadFile(existing); string(got) != "original" {
		t.Errorf("existing file now reads %q", got)
	}
	// Retrying cannot make the name free, so the session ends and its bytes go
	// with it instead of sitting on disk until the TTL.
	if _, err := os.Stat(staged); !os.IsNotExist(err) {
		t.Errorf("staged file survived a commit that can never succeed: %v", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("staging dir still holds %d entries after a refused commit", got)
	}
}

// A commit that failed for a reason the client can outlast keeps the session,
// so resending the last chunk lands the file without restaging it.
func TestATransientCommitFailureKeepsTheSessionForARetry(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	// A file where the destination directory should be makes MkdirAll fail
	// with a plain I/O error rather than a vfs sentinel.
	blocker := filepath.Join(root, "album")
	if err := os.WriteFile(blocker, nil, 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}
	content := []byte("worth keeping")
	total := int64(len(content))
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest,
		RootDir:     "album",
		FileName:    "photo.jpg",
		TotalSize:   total,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	_, err = writeChunk(store, dest, created.SessionID, 0, total-1, total, content)
	if err == nil || errors.Is(err, vfs.ErrConflict) {
		t.Fatalf("commit into a blocked directory returned %v, want a plain I/O error", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 1 {
		t.Fatalf("staging dir holds %d entries after a transient failure, want 1", got)
	}

	if err := os.Remove(blocker); err != nil {
		t.Fatalf("unblock: %v", err)
	}
	if _, err := writeChunk(store, dest, created.SessionID, 0, total-1, total, content); err != nil {
		t.Fatalf("retrying the last chunk: %v", err)
	}
	if got, _ := os.ReadFile(filepath.Join(root, "album", "photo.jpg")); !bytes.Equal(got, content) {
		t.Errorf("committed file is %q, want %q", got, content)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("staging dir still holds %d entries after the retried commit", got)
	}
}

func TestCloseRemovesEveryStagedFile(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	for _, name := range []string{"a.bin", "b.bin"} {
		id := openSession(t, store, dest, name, 1024)
		if _, err := writeChunk(store, dest, id, 0, 511, 1024, make([]byte, 512)); err != nil {
			t.Fatalf("chunk: %v", err)
		}
	}
	if err := store.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("close left %d staged file(s) behind", got)
	}
}

func TestCommitWithOverwriteReplacesTheFile(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	existing := filepath.Join(root, "taken.txt")
	if err := os.WriteFile(existing, []byte("original"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}

	if _, err := commitWhole(t, store, dest, "taken.txt", true, []byte("replacement")); err != nil {
		t.Fatalf("commit: %v", err)
	}
	if got, _ := os.ReadFile(existing); string(got) != "replacement" {
		t.Errorf("file reads %q, want the replacement", got)
	}
}

func openAs(store *uploadutil.SessionStore, dest uploadutil.Destination, userID int64, name string) (string, error) {
	result, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest,
		FileName:    name,
		TotalSize:   16,
		UserID:      userID,
	})
	return result.SessionID, err
}

// Every session holds an open file and a staged temp file for up to the TTL,
// and nothing capped how many one client could open (#2756). Past the
// per-user cap a new session is refused before anything is staged, without
// touching anyone else's.
func TestCreateSessionCapsSessionsPerUser(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	const alice, bob = 1, 2
	var first string
	for i := range uploadutil.MaxSessionsPerUser {
		id, err := openAs(store, dest, alice, fmt.Sprintf("f%d.bin", i))
		if err != nil {
			t.Fatalf("session %d: %v", i, err)
		}
		if i == 0 {
			first = id
		}
	}
	if _, err := openAs(store, dest, alice, "one-too-many.bin"); !errors.Is(err, uploadutil.ErrTooManySessions) {
		t.Fatalf("session past the cap = %v, want ErrTooManySessions", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != uploadutil.MaxSessionsPerUser {
		t.Errorf("staged %d files, want %d: the refused session left one behind", got, uploadutil.MaxSessionsPerUser)
	}
	if _, err := openAs(store, dest, bob, "bob.bin"); err != nil {
		t.Errorf("another user's session was refused: %v", err)
	}

	// Ending a session gives its slot back.
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: first, UserID: alice}); err != nil {
		t.Fatal(err)
	}
	if _, err := openAs(store, dest, alice, "again.bin"); err != nil {
		t.Errorf("a session after one ended was refused: %v", err)
	}
}

// The process holds at most MaxSessions open files, however many accounts
// share it.
func TestCreateSessionCapsSessionsOverall(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	for i := range uploadutil.MaxSessions {
		if _, err := openAs(store, dest, int64(1+i/uploadutil.MaxSessionsPerUser), fmt.Sprintf("f%d.bin", i)); err != nil {
			t.Fatalf("session %d: %v", i, err)
		}
	}
	if _, err := openAs(store, dest, 1_000_000, "fresh-user.bin"); !errors.Is(err, uploadutil.ErrTooManySessions) {
		t.Errorf("session past the overall cap = %v, want ErrTooManySessions", err)
	}
}

// An expired session holds no slot even before the sweeper's next tick: it is
// dropped, staged bytes and all, when its owner opens another.
func TestExpiredSessionsDoNotCountTowardTheCap(t *testing.T) {
	t.Parallel()

	now := time.Now()
	var clock sync.Mutex
	store := uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{
		StagingDir: filepath.Join(t.TempDir(), "upload-sessions"),
		Now: func() time.Time {
			clock.Lock()
			defer clock.Unlock()
			return now
		},
	})
	t.Cleanup(func() { _ = store.Close() })
	dest, _ := newTestDestination(t)
	for i := range uploadutil.MaxSessionsPerUser {
		if _, err := openAs(store, dest, 1, fmt.Sprintf("f%d.bin", i)); err != nil {
			t.Fatalf("session %d: %v", i, err)
		}
	}

	clock.Lock()
	now = now.Add(uploadutil.DefaultSessionTTL + time.Minute)
	clock.Unlock()
	if _, err := openAs(store, dest, 1, "after-expiry.bin"); err != nil {
		t.Fatalf("a session after every other one expired was refused: %v", err)
	}
	if got := stagedCount(t, store.StagingDir()); got != 1 {
		t.Errorf("staged %d files, want only the new session's", got)
	}
}

// A commit that replaces a file on the internal device runs BeforeOverwrite
// while the old content is still there (#2992). A new file, and a file on a
// device addressed by serial, do not run it.
func TestCommitRunsBeforeOverwriteOnlyWhenReplacing(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, root := newLocalDestination(t)
	usb, err := vfs.NewLocalVFS(t.TempDir(), vfs.FilesNamespace("USB1"))
	if err != nil {
		t.Fatalf("NewLocalVFS: %v", err)
	}
	if err := dest.Registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("USB1")}, usb); err != nil {
		t.Fatalf("register device namespace: %v", err)
	}
	if err := usb.Write(context.Background(), "deck.qslide", strings.NewReader("on usb"), vfs.WriteOptions{}); err != nil {
		t.Fatalf("seed device: %v", err)
	}
	if err := os.WriteFile(filepath.Join(root, "deck.qslide"), []byte("original"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}

	var seen []string
	commit := func(serial, name string) {
		t.Helper()
		content := []byte("replacement")
		total := int64(len(content))
		created, err := store.CreateSession(uploadutil.CreateSessionParams{
			Destination: dest, FileName: name, TotalSize: total, Serial: serial, Overwrite: true,
		})
		if err != nil {
			t.Fatalf("create session: %v", err)
		}
		if _, err := store.WriteChunk(uploadutil.WriteChunkParams{
			Ctx: context.Background(), Destination: dest, SessionID: created.SessionID,
			Range: uploadutil.ContentRange{Start: 0, End: total - 1, Total: total}, Body: bytes.NewReader(content),
			BeforeOverwrite: func(p string) {
				old, _ := os.ReadFile(filepath.Join(root, p))
				seen = append(seen, p+"="+string(old))
			},
		}); err != nil {
			t.Fatalf("commit %s: %v", name, err)
		}
	}
	commit("", "deck.qslide")
	commit("", "new.qslide")
	commit("USB1", "deck.qslide")

	if want := []string{"deck.qslide=original"}; !slices.Equal(seen, want) {
		t.Errorf("BeforeOverwrite saw %q, want %q", seen, want)
	}
}

// pluggableDrive reports one USB drive at mountPoint until it is unplugged.
type pluggableDrive struct {
	mountPoint string
	unplugged  atomic.Bool
}

func (d *pluggableDrive) DetectDevices() ([]storageutil.Device, error) {
	if d.unplugged.Load() {
		return nil, nil
	}
	return []storageutil.Device{{Name: "USB", MountPoint: d.mountPoint, UsbInfo: usbDrive{}}}, nil
}

// usbStaging is a USB drive registered the way production registers one,
// beside an in-memory internal drive, with the host directories a test checks.
type usbStaging struct {
	dest     uploadutil.Destination
	drive    *pluggableDrive
	svc      *storageutil.StorageService
	filesDir string
	// stagingDir is where the drive's sessions should stage: beside its files
	// directory, the way its trash is.
	stagingDir string
}

func newUSBStaging(t *testing.T) usbStaging {
	t.Helper()
	drive := &pluggableDrive{mountPoint: t.TempDir()}
	svc := storageutil.NewStorageService(drive)
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: "files"}, vfs.NewMemVFS("files")); err != nil {
		t.Fatalf("register files namespace: %v", err)
	}
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: svc}); err != nil {
		t.Fatal(err)
	}
	dataDir := storageutil.GetDataDirForDevice(drive.mountPoint)
	return usbStaging{
		dest:       uploadutil.Destination{Registry: registry, EventBus: eventbus.New()},
		drive:      drive,
		svc:        svc,
		filesDir:   storageutil.ConstructFilesDir(dataDir),
		stagingDir: filepath.Join(dataDir, "tmp", "upload-sessions"),
	}
}

func openDeviceSession(t *testing.T, store *uploadutil.SessionStore, dest uploadutil.Destination, name string, size int64) string {
	t.Helper()
	result, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest,
		FileName:    name,
		TotalSize:   size,
		Serial:      deviceSerial,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	return result.SessionID
}

// onlyStagedFile is the one file staged in dir.
func onlyStagedFile(t *testing.T, dir string) string {
	t.Helper()
	matches, err := filepath.Glob(filepath.Join(dir, "upload-*.part"))
	if err != nil || len(matches) != 1 {
		t.Fatalf("want exactly one staged file in %s, got %v (%v)", dir, matches, err)
	}
	return matches[0]
}

// An upload to a USB drive is staged on that drive, so its commit is a rename
// on one filesystem rather than a copy off the internal drive (#3970).
func TestADeviceUploadIsStagedOnThatDevice(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	usb := newUSBStaging(t)
	content := []byte("staged beside the files, not on the internal drive")
	total := int64(len(content))

	id := openDeviceSession(t, store, usb.dest, "takeout.zip", total)
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("the internal staging dir holds %d file(s) for a USB upload", got)
	}
	staged := onlyStagedFile(t, usb.stagingDir)
	if rel, err := filepath.Rel(usb.filesDir, staged); err != nil || !strings.HasPrefix(rel, "..") {
		t.Errorf("staged at %s, inside the files directory %s", staged, usb.filesDir)
	}
	before, err := os.Stat(staged)
	if err != nil {
		t.Fatalf("stat staged file: %v", err)
	}

	result, err := writeChunk(store, usb.dest, id, 0, total-1, total, content)
	if err != nil {
		t.Fatalf("commit: %v", err)
	}
	if !result.Complete || result.Serial != deviceSerial {
		t.Fatalf("commit reported %+v", result)
	}
	committed := filepath.Join(usb.filesDir, "takeout.zip")
	after, err := os.Stat(committed)
	if err != nil {
		t.Fatalf("stat committed file: %v", err)
	}
	if !os.SameFile(before, after) {
		t.Error("the committed file is a copy; the staged file should have been renamed into place")
	}
	if got, _ := os.ReadFile(committed); !bytes.Equal(got, content) {
		t.Errorf("committed file is %q, want %q", got, content)
	}
	if got := stagedCount(t, usb.stagingDir); got != 0 {
		t.Errorf("the drive's staging dir still holds %d entries after the commit", got)
	}
}

// When the staged file and its destination are on different filesystems the
// commit cannot rename, and falls back to a copy that still lands the whole
// file and leaves nothing staged.
func TestACrossDeviceCommitFallsBackToACopy(t *testing.T) {
	t.Parallel()

	const otherFS = "/dev/shm"
	dest, root := newLocalDestination(t)
	if !onDifferentFilesystems(t, otherFS, root) {
		t.Skipf("%s is not a separate filesystem from %s here", otherFS, root)
	}
	stagingRoot, err := os.MkdirTemp(otherFS, "quark-upload-staging-")
	if err != nil {
		t.Skipf("cannot stage on %s: %v", otherFS, err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(stagingRoot) })
	store := uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{
		StagingDir: filepath.Join(stagingRoot, "upload-sessions"),
	})
	t.Cleanup(func() { _ = store.Close() })

	content := []byte("copied across filesystems")
	staged, err := commitWhole(t, store, dest, "far.bin", false, content)
	if err != nil {
		t.Fatalf("commit: %v", err)
	}
	if got, _ := os.ReadFile(filepath.Join(root, "far.bin")); !bytes.Equal(got, content) {
		t.Errorf("committed file is %q, want %q", got, content)
	}
	if _, err := os.Stat(staged); !os.IsNotExist(err) {
		t.Errorf("the staged file survived the copy: %v", err)
	}
}

// onDifferentFilesystems reports whether a exists and sits on another
// filesystem from b, where a rename between them is EXDEV.
func onDifferentFilesystems(t *testing.T, a, b string) bool {
	t.Helper()
	ai, err := os.Stat(a)
	if err != nil {
		return false
	}
	bi, err := os.Stat(b)
	if err != nil {
		t.Fatalf("stat %s: %v", b, err)
	}
	as, aok := ai.Sys().(*syscall.Stat_t)
	bs, bok := bi.Sys().(*syscall.Stat_t)
	return aok && bok && as.Dev != bs.Dev
}

// An expired or canceled session on a USB drive takes its staged bytes with
// it, the same as one on the internal drive.
func TestDeviceSessionsLeaveNothingStagedWhenTheyEnd(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	usb := newUSBStaging(t)

	canceled := openDeviceSession(t, store, usb.dest, "canceled.bin", 1024)
	if _, err := writeChunk(store, usb.dest, canceled, 0, 511, 1024, make([]byte, 512)); err != nil {
		t.Fatalf("chunk: %v", err)
	}
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: canceled}); err != nil {
		t.Fatalf("delete session: %v", err)
	}
	if got := stagedCount(t, usb.stagingDir); got != 0 {
		t.Errorf("a canceled session left %d staged file(s) on the drive", got)
	}

	openDeviceSession(t, store, usb.dest, "abandoned.bin", 1024)
	if result := store.Sweep(time.Now().Add(2 * uploadutil.DefaultSessionTTL)); result.Expired != 1 {
		t.Fatalf("sweep expired %d sessions, want 1", result.Expired)
	}
	if got := stagedCount(t, usb.stagingDir); got != 0 {
		t.Errorf("an expired session left %d staged file(s) on the drive", got)
	}
}

// Sessions live in memory, so a process that dies mid-upload strands its
// staged file. The next process clears what an earlier one left in a staging
// dir the first time it stages there, on the internal drive and on a USB
// drive alike, and never touches a file one of its own sessions staged.
func TestARestartClearsPartFilesAnEarlierProcessStranded(t *testing.T) {
	t.Parallel()

	usb := newUSBStaging(t)
	internalDir := filepath.Join(t.TempDir(), "upload-sessions")
	crashed := uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{StagingDir: internalDir})
	// The crashed process never closed its store, so its staged files stayed.
	// Closing it after the test only releases its file handles.
	t.Cleanup(func() { _ = crashed.Close() })
	openSession(t, crashed, usb.dest, "internal.bin", 1024)
	openDeviceSession(t, crashed, usb.dest, "usb.bin", 1024)
	stranded := []string{onlyStagedFile(t, internalDir), onlyStagedFile(t, usb.stagingDir)}
	var unrelated []string
	for _, dir := range []string{internalDir, usb.stagingDir} {
		p := filepath.Join(dir, "not-an-upload.txt")
		if err := os.WriteFile(p, []byte("x"), 0o600); err != nil {
			t.Fatalf("seed %s: %v", p, err)
		}
		unrelated = append(unrelated, p)
	}

	restarted := uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{StagingDir: internalDir})
	t.Cleanup(func() { _ = restarted.Close() })
	openSession(t, restarted, usb.dest, "internal.bin", 1024)
	openDeviceSession(t, restarted, usb.dest, "usb.bin", 1024)
	own := []string{onlyStagedFile(t, internalDir), onlyStagedFile(t, usb.stagingDir)}

	for _, p := range stranded {
		if _, err := os.Stat(p); !os.IsNotExist(err) {
			t.Errorf("%s survived the restart: %v", p, err)
		}
	}
	for _, p := range unrelated {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("%s is not a staged upload but was removed: %v", p, err)
		}
	}
	// A second session in the same dirs leaves the first one's file alone.
	openSession(t, restarted, usb.dest, "internal-2.bin", 1024)
	openDeviceSession(t, restarted, usb.dest, "usb-2.bin", 1024)
	for _, p := range own {
		if _, err := os.Stat(p); err != nil {
			t.Errorf("a live session's staged file %s was removed: %v", p, err)
		}
	}
}

// Unplugging the drive mid-upload ends the session with the "no destination"
// error the handler answers as 404, rather than writing on to a stale file or
// falling back to the internal drive, and an upload to the internal drive
// goes on working.
func TestUnpluggingTheDeviceMidUploadEndsItsSession(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	usb := newUSBStaging(t)

	id := openDeviceSession(t, store, usb.dest, "unplugged.bin", 1024)
	if _, err := writeChunk(store, usb.dest, id, 0, 511, 1024, make([]byte, 512)); err != nil {
		t.Fatalf("first chunk: %v", err)
	}
	usb.drive.unplugged.Store(true)
	usb.svc.InvalidateDeviceCache()

	_, err := writeChunk(store, usb.dest, id, 512, 1023, 1024, make([]byte, 512))
	if !errors.Is(err, uploadutil.ErrNoDestination) || !errors.Is(err, vfs.ErrNotFound) {
		t.Fatalf("chunk after unplugging = %v, want ErrNoDestination wrapping vfs.ErrNotFound", err)
	}
	if _, err := store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: id}); !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("the session outlived its drive: %v", err)
	}
	finished := store.ListSessions(uploadutil.ListSessionsParams{}).Finished
	if len(finished) != 1 || finished[0].SessionID != id || finished[0].State != uploadutil.SessionFailed {
		t.Errorf("unplugged session listed as %+v, want one failed session %s", finished, id)
	}
	if got := stagedCount(t, usb.stagingDir); got != 0 {
		t.Errorf("the ended session left %d staged file(s)", got)
	}
	if got := stagedCount(t, store.StagingDir()); got != 0 {
		t.Errorf("the internal staging dir picked up %d file(s)", got)
	}
	if _, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: usb.dest, FileName: "again.bin", TotalSize: 1, Serial: deviceSerial,
	}); !errors.Is(err, uploadutil.ErrNoDestination) {
		t.Errorf("a session on the unplugged drive opened: %v", err)
	}

	internal := openSession(t, store, usb.dest, "internal.bin", 3)
	result, err := writeChunk(store, usb.dest, internal, 0, 2, 3, []byte("yes"))
	if err != nil || !result.Complete {
		t.Errorf("an internal upload after the unplug = %+v, %v", result, err)
	}
}
