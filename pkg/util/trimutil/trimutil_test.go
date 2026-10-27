package trimutil

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// gopFixture is three seconds of H.264 and AAC with keyframes every half
// second, from videoutil's corpus.
const gopFixture = "../videoutil/testdata/h264-gop12.mp4"

const testSerial = "test-serial"

type harness struct {
	fsys     *vfs.MemVFS
	registry vfs.Registry
	queue    *jobutil.Queue
	events   <-chan eventbus.Event
}

// newHarness is a queue with the trim kind registered around trimFile (nil
// for the real one), over a namespace holding the fixture at clip.mp4.
func newHarness(t *testing.T, trimFile TrimFileFunc) harness {
	t.Helper()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(testSerial))
	f, err := os.Open(gopFixture)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if err := fsys.Write(context.Background(), "clip.mp4", f, vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace(testSerial)}, fsys); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	bus := eventbus.New()
	events, unsub := bus.Subscribe("trimutil-test")
	t.Cleanup(unsub)
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database, EventBus: bus})
	queue.Register(jobutil.RegisterParams{Kind: Kind, Handler: NewHandler(NewHandlerParams{
		Registry: registry, Database: database, EventBus: bus, TrimFile: trimFile,
	})})
	return harness{fsys: fsys, registry: registry, queue: queue, events: events}
}

func (h harness) enqueue(t *testing.T, p Params) jobutil.Job {
	t.Helper()
	result, err := Enqueue(context.Background(), EnqueueParams{Queue: h.queue, Registry: h.registry, Params: p})
	if err != nil {
		t.Fatal(err)
	}
	return result.Job
}

// run starts the dispatcher and waits for job id to end.
func (h harness) run(t *testing.T, id int64) jobutil.Job {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		h.queue.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	deadline := time.Now().Add(10 * time.Second)
	for {
		res, err := h.queue.Get(context.Background(), jobutil.GetParams{ID: id})
		if err != nil {
			t.Fatal(err)
		}
		switch res.Job.Status {
		case jobutil.StatusCompleted, jobutil.StatusFailed, jobutil.StatusCanceled:
			return res.Job
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %d is still %s", id, res.Job.Status)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func (h harness) names(t *testing.T) []string {
	t.Helper()
	list, err := h.fsys.List(context.Background(), "", nil)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, fi := range list {
		out = append(out, fi.Name)
	}
	return out
}

func TestEnqueueRefusesWhatCannotBeTrimmed(t *testing.T) {
	h := newHarness(t, nil)
	if err := h.fsys.Write(context.Background(), "notes.mp4", strings.NewReader("not a video"), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	cases := []struct {
		name string
		p    Params
		want error
	}{
		{"a negative start", Params{RelPath: "clip.mp4", Serial: testSerial, StartMs: -1, EndMs: 1000}, ErrInvalidRange},
		{"an end at the start", Params{RelPath: "clip.mp4", Serial: testSerial, StartMs: 1000, EndMs: 1000}, ErrInvalidRange},
		{"no path", Params{Serial: testSerial, StartMs: 0, EndMs: 1000}, ErrInvalidPath},
		{"the device root", Params{RelPath: "/", Serial: testSerial, StartMs: 0, EndMs: 1000}, ErrInvalidPath},
		{"a missing file", Params{RelPath: "gone.mp4", Serial: testSerial, StartMs: 0, EndMs: 1000}, ErrSourceNotFound},
		{"an unattached device", Params{RelPath: "clip.mp4", Serial: "unplugged", StartMs: 0, EndMs: 1000}, ErrSourceNotFound},
		{"a file that is not a video", Params{RelPath: "notes.mp4", Serial: testSerial, StartMs: 0, EndMs: 1000}, videoutil.ErrNotAVideo},
		{"a start at the end", Params{RelPath: "clip.mp4", Serial: testSerial, StartMs: 3000, EndMs: 3500}, videoutil.ErrStartPastEnd},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Enqueue(context.Background(), EnqueueParams{Queue: h.queue, Registry: h.registry, Params: c.p})
			if !errors.Is(err, c.want) {
				t.Fatalf("Enqueue = %v, want %v", err, c.want)
			}
		})
	}
	list, err := h.queue.List(context.Background(), jobutil.ListParams{Kinds: []string{Kind}})
	if err != nil || len(list.Jobs) != 0 {
		t.Fatalf("refused trims queued %v (%v), want none", list.Jobs, err)
	}
}

// TestTrimJobSavesItsResult runs a trim job from queued to completed: it is
// named for its video, runs in the copy lane, reports no progress until it
// ends, saves where the clip landed and where it is shown from, and announces
// the clip with an upload event.
func TestTrimJobSavesItsResult(t *testing.T) {
	h := newHarness(t, nil)
	queued := h.enqueue(t, Params{RelPath: "clip.mp4", Serial: testSerial, StartMs: 1200, EndMs: 2200})
	if queued.Name != "Trim clip.mp4" || queued.Lane != LaneCopy || queued.Status != jobutil.StatusPending {
		t.Fatalf("queued = %+v, want a pending Trim clip.mp4 in the copy lane", queued)
	}

	job := h.run(t, queued.ID)
	if job.Status != jobutil.StatusCompleted || job.Progress != 1 {
		t.Fatalf("job = %s at %v (%s), want completed at 1", job.Status, job.Progress, job.Error)
	}
	var result Result
	if err := json.Unmarshal(job.Detail, &result); err != nil {
		t.Fatal(err)
	}
	if result != (Result{RelPath: "clip_trimmed.mp4", ActualStartMs: 1200}) {
		t.Fatalf("detail = %s, want clip_trimmed.mp4 shown from 1200ms", job.Detail)
	}
	for upload := false; !upload; {
		select {
		case e := <-h.events:
			if e.Kind == eventbus.EventJobProgress {
				t.Errorf("a trim reported progress %+v; it has none to report", e.Data)
			}
			upload = e.Kind == eventbus.EventUpload
			if upload && (e.Path != "clip_trimmed.mp4" || e.DeviceSerial != testSerial) {
				t.Errorf("upload = %+v, want clip_trimmed.mp4 on %s", e, testSerial)
			}
		case <-time.After(time.Second):
			t.Fatal("the trim published no upload")
		}
	}
}

// TestCancelAsTheClipLandsRemovesIt cancels the job in the moment after the
// clip has landed and before the job ends: the job stays canceled, and the
// clip it no longer wants is removed rather than left behind.
func TestCancelAsTheClipLandsRemovesIt(t *testing.T) {
	var queue *jobutil.Queue
	h := newHarness(t, func(ctx context.Context, p videoutil.TrimFileParams) (videoutil.TrimFileResult, error) {
		result, err := videoutil.TrimFile(ctx, p)
		if err != nil {
			return result, err
		}
		if _, err := queue.Cancel(context.Background(), jobutil.CancelParams{ID: jobutil.JobID(ctx)}); err != nil {
			return result, err
		}
		return result, nil
	})
	queue = h.queue

	job := h.run(t, h.enqueue(t, Params{RelPath: "clip.mp4", Serial: testSerial, StartMs: 0, EndMs: 1000}).ID)
	if job.Status != jobutil.StatusCanceled || string(job.Detail) != "{}" {
		t.Fatalf("job = %s with detail %s, want canceled with none", job.Status, job.Detail)
	}
	// The run settles after Cancel records the status, so give it a moment.
	deadline := time.Now().Add(5 * time.Second)
	for len(h.names(t)) != 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if got := h.names(t); len(got) != 1 || got[0] != "clip.mp4" {
		t.Fatalf("the folder holds %v, want only clip.mp4", got)
	}
}

func TestRetryOfAGoneSourceIsRefused(t *testing.T) {
	h := newHarness(t, nil)
	handler := NewHandler(NewHandlerParams{Registry: h.registry})
	raw, err := json.Marshal(Params{RelPath: "gone.mp4", Serial: testSerial, StartMs: 0, EndMs: 1000})
	if err != nil {
		t.Fatal(err)
	}
	if err := handler.Validate(raw); !errors.Is(err, ErrSourceNotFound) {
		t.Fatalf("Validate = %v, want ErrSourceNotFound", err)
	}
}
