package uploadutil_test

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ListSessions is what the Jobs page shows for uploads (#3971): what each
// session has committed, whether it is still taking chunks or committing, and
// how the recent ones ended.

// testClock is a clock a test moves by hand.
type testClock struct {
	mu  sync.Mutex
	now time.Time
}

func (c *testClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *testClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

func newClockedStore(t *testing.T) (*uploadutil.SessionStore, *testClock) {
	t.Helper()
	clock := &testClock{now: time.Date(2026, 11, 4, 12, 0, 0, 0, time.UTC)}
	store := uploadutil.NewSessionStore(uploadutil.NewSessionStoreParams{
		StagingDir: filepath.Join(t.TempDir(), "upload-sessions"),
		Now:        clock.Now,
	})
	t.Cleanup(func() { _ = store.Close() })
	return store, clock
}

func openFor(t *testing.T, store *uploadutil.SessionStore, dest uploadutil.Destination, userID int64, name string, size int64) string {
	t.Helper()
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest, FileName: name, TotalSize: size, UserID: userID,
	})
	if err != nil {
		t.Fatalf("create session %s: %v", name, err)
	}
	return created.SessionID
}

func chunkFor(store *uploadutil.SessionStore, dest uploadutil.Destination, userID int64, id string, start, end, total int64) (uploadutil.WriteChunkResult, error) {
	return store.WriteChunk(uploadutil.WriteChunkParams{
		Ctx: context.Background(), Destination: dest, SessionID: id, UserID: userID,
		Range: uploadutil.ContentRange{Start: start, End: end, Total: total},
		Body:  bytes.NewReader(make([]byte, end-start+1)),
	})
}

func TestListSessionsShowsOnlyTheCallersSessions(t *testing.T) {
	t.Parallel()

	store, _ := newClockedStore(t)
	dest, _ := newTestDestination(t)
	const owner, stranger = int64(7), int64(8)
	mine := openFor(t, store, dest, owner, "mine.bin", 1024)
	openFor(t, store, dest, stranger, "theirs.bin", 1024)

	got := store.ListSessions(uploadutil.ListSessionsParams{UserID: owner})
	if len(got.Active) != 1 || got.Active[0].SessionID != mine {
		t.Fatalf("owner sees %+v, want only %s", got.Active, mine)
	}
	if s := got.Active[0]; s.FileName != "mine.bin" || s.TotalSize != 1024 || s.Offset != 0 || s.State != uploadutil.SessionUploading {
		t.Errorf("summary is %+v", s)
	}
}

func TestListSessionsTracksTheCommittedOffset(t *testing.T) {
	t.Parallel()

	store, clock := newClockedStore(t)
	dest, _ := newTestDestination(t)
	id := openFor(t, store, dest, 1, "big.bin", 1024)

	clock.Advance(time.Second)
	if _, err := chunkFor(store, dest, 1, id, 0, 511, 1024); err != nil {
		t.Fatalf("chunk: %v", err)
	}
	got := store.ListSessions(uploadutil.ListSessionsParams{UserID: 1}).Active[0]
	if got.Offset != 512 {
		t.Errorf("offset is %d, want 512", got.Offset)
	}
	if want := clock.Now(); !got.UpdatedAt.Equal(want) {
		t.Errorf("updatedAt is %v, want the time of the last chunk %v", got.UpdatedAt, want)
	}
}

// Committing flushes and moves the whole file, which can take minutes on a
// slow disk. The list has to say so, and must not wait on the session's lock
// to say it: the commit holds that lock throughout.
func TestListSessionsReportsCommittingWithoutBlocking(t *testing.T) {
	t.Parallel()

	store, _ := newClockedStore(t)
	dest, root := newLocalDestination(t)
	if err := os.WriteFile(filepath.Join(root, "deck.qslide"), []byte("original"), 0o644); err != nil {
		t.Fatalf("seed: %v", err)
	}
	content := []byte("replacement")
	total := int64(len(content))
	created, err := store.CreateSession(uploadutil.CreateSessionParams{
		Destination: dest, FileName: "deck.qslide", TotalSize: total, Overwrite: true, UserID: 1,
	})
	if err != nil {
		t.Fatalf("create session: %v", err)
	}

	var during uploadutil.ListSessionsResult
	if _, err := store.WriteChunk(uploadutil.WriteChunkParams{
		Ctx: context.Background(), Destination: dest, SessionID: created.SessionID, UserID: 1,
		Range: uploadutil.ContentRange{Start: 0, End: total - 1, Total: total}, Body: bytes.NewReader(content),
		// Runs inside the commit, with the session's lock held.
		BeforeOverwrite: func(string) {
			during = store.ListSessions(uploadutil.ListSessionsParams{UserID: 1})
		},
	}); err != nil {
		t.Fatalf("commit: %v", err)
	}

	if len(during.Active) != 1 || during.Active[0].State != uploadutil.SessionCommitting || during.Active[0].Offset != total {
		t.Errorf("during the commit the list said %+v, want one committing session at offset %d", during.Active, total)
	}
}

func TestListSessionsKeepsHowEachSessionEnded(t *testing.T) {
	t.Parallel()

	store, clock := newClockedStore(t)
	dest, fsys := newTestDestination(t)

	done := openFor(t, store, dest, 1, "done.bin", 4)
	if _, err := chunkFor(store, dest, 1, done, 0, 3, 4); err != nil {
		t.Fatalf("commit: %v", err)
	}

	clock.Advance(time.Second)
	canceled := openFor(t, store, dest, 1, "canceled.bin", 4)
	if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: canceled, UserID: 1}); err != nil {
		t.Fatalf("delete: %v", err)
	}

	clock.Advance(time.Second)
	taken := openFor(t, store, dest, 1, "taken.bin", 4)
	// The name is taken after the session opened, so the commit can never land.
	if err := fsys.Write(context.Background(), "taken.bin", bytes.NewReader([]byte("x")), vfs.WriteOptions{}); err != nil {
		t.Fatalf("seed: %v", err)
	}
	if _, err := chunkFor(store, dest, 1, taken, 0, 3, 4); err == nil {
		t.Fatal("commit onto a taken name succeeded")
	}

	clock.Advance(time.Second)
	expired := openFor(t, store, dest, 1, "expired.bin", 4)
	store.Sweep(clock.Now().Add(2 * uploadutil.DefaultSessionTTL))

	got := store.ListSessions(uploadutil.ListSessionsParams{UserID: 1})
	if len(got.Active) != 0 {
		t.Errorf("%d sessions still active", len(got.Active))
	}
	want := []struct {
		id    string
		state uploadutil.SessionState
	}{
		{expired, uploadutil.SessionExpired},
		{taken, uploadutil.SessionFailed},
		{canceled, uploadutil.SessionCanceled},
		{done, uploadutil.SessionCompleted},
	}
	if len(got.Finished) != len(want) {
		t.Fatalf("finished is %+v, want %d entries", got.Finished, len(want))
	}
	for i, w := range want {
		if got.Finished[i].SessionID != w.id || got.Finished[i].State != w.state {
			t.Errorf("finished[%d] is %s %s, want %s %s", i, got.Finished[i].SessionID, got.Finished[i].State, w.id, w.state)
		}
	}
	if got.Finished[1].Error == "" {
		t.Error("the failed session carries no error")
	}
	if got.Finished[3].Offset != 4 {
		t.Errorf("the completed session reports offset %d, want 4", got.Finished[3].Offset)
	}
}

func TestFinishedSessionsAreBoundedByCountAndAge(t *testing.T) {
	t.Parallel()

	store, clock := newClockedStore(t)
	dest, _ := newTestDestination(t)
	var last string
	for range uploadutil.MaxFinishedSessionsPerUser + 5 {
		last = openFor(t, store, dest, 1, "gone.bin", 4)
		if _, err := store.DeleteSession(uploadutil.DeleteSessionParams{SessionID: last, UserID: 1}); err != nil {
			t.Fatalf("delete: %v", err)
		}
	}

	got := store.ListSessions(uploadutil.ListSessionsParams{UserID: 1}).Finished
	if len(got) != uploadutil.MaxFinishedSessionsPerUser {
		t.Fatalf("kept %d finished sessions, want %d", len(got), uploadutil.MaxFinishedSessionsPerUser)
	}
	if got[0].SessionID != last {
		t.Errorf("newest finished session is %s, want %s", got[0].SessionID, last)
	}

	clock.Advance(uploadutil.FinishedSessionMaxAge + time.Second)
	if got := store.ListSessions(uploadutil.ListSessionsParams{UserID: 1}).Finished; len(got) != 0 {
		t.Errorf("kept %d finished sessions past their age", len(got))
	}
}

// A fast upload sends many chunks a second; only one per ProgressInterval
// asks for a progress event.
func TestProgressIsDueAtMostOncePerInterval(t *testing.T) {
	t.Parallel()

	store, clock := newClockedStore(t)
	dest, _ := newTestDestination(t)
	const chunks = 40
	total := int64(chunks * 10)
	id := openFor(t, store, dest, 1, "fast.bin", total)

	due := 0
	for i := range int64(chunks - 1) {
		clock.Advance(100 * time.Millisecond)
		result, err := chunkFor(store, dest, 1, id, i*10, i*10+9, total)
		if err != nil {
			t.Fatalf("chunk %d: %v", i, err)
		}
		if result.ProgressDue {
			due++
		}
	}
	// 39 chunks over 3.9 s: due at 2.0 s only, the next would be at 4.0 s.
	if due != 1 {
		t.Errorf("progress was due %d times, want 1", due)
	}
}
