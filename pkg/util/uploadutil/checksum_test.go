package uploadutil_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"runtime"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/uploadutil"
)

// patternReader is an endless, non-uniform stream, so a test can send a large
// upload without holding it.
type patternReader struct{ next byte }

func (r *patternReader) Read(p []byte) (int, error) {
	for i := range p {
		p[i] = r.next
		r.next += 7
	}
	return len(p), nil
}

func patternSHA256(t *testing.T, size int64) string {
	t.Helper()
	digest := sha256.New()
	if _, err := io.CopyN(digest, &patternReader{}, size); err != nil {
		t.Fatalf("hash pattern: %v", err)
	}
	return hex.EncodeToString(digest.Sum(nil))
}

// sendPattern uploads size bytes of the pattern in chunkSize pieces and
// returns the last chunk's outcome.
func sendPattern(
	t *testing.T, store *uploadutil.SessionStore, dest uploadutil.Destination, sessionID string, size, chunkSize int64,
) (uploadutil.WriteChunkResult, error) {
	t.Helper()
	source := &patternReader{}
	var (
		result uploadutil.WriteChunkResult
		err    error
	)
	for start := int64(0); start < size; start += chunkSize {
		end := min(start+chunkSize, size)
		result, err = store.WriteChunk(uploadutil.WriteChunkParams{
			Ctx:         context.Background(),
			Destination: dest,
			SessionID:   sessionID,
			Range:       uploadutil.ContentRange{Start: start, End: end - 1, Total: size},
			Body:        io.LimitReader(source, end-start),
		})
		if err != nil && end < size {
			t.Fatalf("chunk [%d,%d) failed: %v", start, end, err)
		}
	}
	return result, err
}

// Hashing the staged file must cost a copy buffer, not the file: uploads are
// as large as a user's videos (#4160). The hash is wrong on purpose, so the
// run covers the hash and stops before the in-memory test namespace would
// take its own copy of the file.
func TestChecksumIsVerifiedWithoutBufferingTheFile(t *testing.T) {
	const (
		size       = int64(64 << 20)
		chunkSize  = int64(1 << 20)
		allocLimit = uint64(8 << 20)
	)
	store := newTestStore(t)
	dest, fsys := newTestDestination(t)
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest, FileName: "video.mov", TotalSize: size,
		SHA256: strings.Repeat("0", 64),
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	var before, after runtime.MemStats
	runtime.GC()
	runtime.ReadMemStats(&before)
	_, err = sendPattern(t, store, dest, created.SessionID, size, chunkSize)
	runtime.ReadMemStats(&after)

	if !errors.Is(err, uploadutil.ErrChecksumMismatch) {
		t.Fatalf("last chunk returned %v, want ErrChecksumMismatch", err)
	}
	if allocated := after.TotalAlloc - before.TotalAlloc; allocated > allocLimit {
		t.Errorf("verifying a %d byte upload allocated %d bytes, want at most %d", size, allocated, allocLimit)
	}
	if _, err := fsys.Stat(context.Background(), "video.mov"); err == nil {
		t.Error("a mismatched upload was written to the namespace")
	}
}

func TestMatchingChecksumCommitsAndIsReported(t *testing.T) {
	t.Parallel()

	const size = int64(3<<20 + 11)
	want := patternSHA256(t, size)
	store := newTestStore(t)
	dest, fsys := newTestDestination(t)
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest, FileName: "photo.jpg", TotalSize: size, SHA256: want,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	result, err := sendPattern(t, store, dest, created.SessionID, size, 1<<20)
	if err != nil {
		t.Fatalf("last chunk failed: %v", err)
	}
	if !result.Complete || result.SHA256 != want {
		t.Errorf("result is complete=%v sha256=%q, want complete with %q", result.Complete, result.SHA256, want)
	}
	if _, err := fsys.Stat(context.Background(), "photo.jpg"); err != nil {
		t.Errorf("the verified upload is not in the namespace: %v", err)
	}
}

func TestMismatchedChecksumEndsTheSession(t *testing.T) {
	t.Parallel()

	const size = int64(1 << 20)
	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest, FileName: "photo.jpg", TotalSize: size, SHA256: strings.Repeat("a", 64),
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}
	if _, err := sendPattern(t, store, dest, created.SessionID, size, size); !errors.Is(err, uploadutil.ErrChecksumMismatch) {
		t.Fatalf("last chunk returned %v, want ErrChecksumMismatch", err)
	}

	_, err = store.DescribeSession(uploadutil.DescribeSessionParams{SessionID: created.SessionID})
	if !errors.Is(err, uploadutil.ErrSessionNotFound) {
		t.Errorf("a mismatched session is still open: %v", err)
	}
	finished := store.ListSessions(uploadutil.ListSessionsParams{}).Finished
	if len(finished) != 1 || finished[0].State != uploadutil.SessionFailed {
		t.Errorf("finished sessions are %+v, want one failed", finished)
	}
}

func TestCreateSessionRejectsAMalformedChecksum(t *testing.T) {
	t.Parallel()

	store := newTestStore(t)
	dest, _ := newTestDestination(t)
	for name, checksum := range map[string]string{
		"uppercase": strings.Repeat("A", 64),
		"short":     strings.Repeat("a", 63),
		"long":      strings.Repeat("a", 65),
		"not hex":   strings.Repeat("g", 64),
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			_, err := store.CreateSession(uploadutil.CreateSessionParams{
				Destination: dest, FileName: "photo.jpg", TotalSize: 1, SHA256: checksum,
			})
			if !errors.Is(err, uploadutil.ErrInvalidRequest) {
				t.Errorf("checksum %q returned %v, want ErrInvalidRequest", checksum, err)
			}
		})
	}
}
