package v0_videos_test

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/trimutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// sparseGOPFixture is four seconds at 24 fps with keyframes at 0 and 3
// seconds only, so a start between them carries the longest lead-in a trim
// can. videoutil's trim_actual_start_test.go derives the start each cut of it
// is shown from out of its keyframe table; these tests pin that the API
// reports that same start, so neither hop can lose it (#3430).
const sparseGOPFixture = "../../../../../pkg/util/videoutil/testdata/h264-gop72.mp4"

// trimmed is a completed trim job's detail.
type trimmed = trimutil.Result

// startQueue runs q's dispatcher until the test ends.
func startQueue(t *testing.T, q *jobutil.Queue) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		q.Run(ctx)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
}

// waitForJob waits for job id to complete, fail, or be canceled.
func waitForJob(t *testing.T, q *jobutil.Queue, id int64) jobutil.Job {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for {
		res, err := q.Get(context.Background(), jobutil.GetParams{ID: id})
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

// trimResult reads the Result out of a completed trim job.
func trimResult(t *testing.T, job jobutil.Job) trimmed {
	t.Helper()
	if job.Status != jobutil.StatusCompleted {
		t.Fatalf("trim job is %s (%s), want completed", job.Status, job.Error)
	}
	var result trimmed
	if err := json.Unmarshal(job.Detail, &result); err != nil || result.RelPath == "" {
		t.Fatalf("trim job detail %s holds no result: %v", job.Detail, err)
	}
	return result
}

// trimOK queues a trim of rel, waits for its job, and reads the result the
// job API hands a client. The worker must be running.
func (h harness) trimOK(t *testing.T, rel string, startMs, endMs int64) trimmed {
	t.Helper()
	id := acceptedJobID(t, h.trim(fmt.Sprintf(`{"relPath":%q,"serial":%q,"startMs":%d,"endMs":%d}`, rel, testSerial, startMs, endMs)))
	waitForJob(t, h.queue, id)
	w := h.get(fmt.Sprintf("/api/v0/jobs/%d", id))
	if w.Code != http.StatusOK {
		t.Fatalf("GET job %d returned %d: %s", id, w.Code, w.Body.String())
	}
	var job jobutil.Job
	if err := json.Unmarshal(w.Body.Bytes(), &job); err != nil {
		t.Fatal(err)
	}
	if job.Kind != trimutil.Kind || job.Name != "Trim "+filepath.Base(rel) || job.Lane != trimutil.LaneCopy {
		t.Errorf("job = %+v, want a %s job named for %s in the copy lane", job, trimutil.Kind, rel)
	}
	return trimResult(t, job)
}

// upload is the next upload event the bus carried, skipping the job_* events
// around it, or false when none came.
func (h harness) upload() (eventbus.Event, bool) {
	for {
		select {
		case e := <-h.events:
			if e.Kind == eventbus.EventUpload {
				return e, true
			}
		case <-time.After(time.Second):
			return eventbus.Event{}, false
		}
	}
}

// cancelingVFS is a namespace whose Write calls cancel with the trim job's
// context once the clip's first bytes have arrived, the way a user pressing
// Cancel on the Jobs page mid-trim does, and then lets the real Write carry
// on. It counts the bytes the trim managed to send.
type cancelingVFS struct {
	vfs.VFS
	cancel func(ctx context.Context)
	sent   atomic.Int64
}

func (c *cancelingVFS) Write(ctx context.Context, p string, r io.Reader, opts vfs.WriteOptions) error {
	r = &countingReader{r: r, n: &c.sent}
	first := make([]byte, 1)
	if _, err := io.ReadFull(r, first); err != nil {
		return err
	}
	c.cancel(ctx)
	return c.VFS.Write(ctx, p, io.MultiReader(strings.NewReader(string(first)), r), opts)
}

type countingReader struct {
	r io.Reader
	n *atomic.Int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n.Add(int64(n))
	return n, err
}

// TestTrimCancelLeavesNoPartialFile cancels a running trim job through the
// jobs API while its clip is being written (#3426): the job ends canceled
// with no result, the trim stops short of the whole clip, nothing is left
// under any _trimmed name or anywhere else in the folder, and no upload event
// tells a file browser to list a clip that is not there.
func TestTrimCancelLeavesNoPartialFile(t *testing.T) {
	h := newHarness(t)
	copyFixture(t, sparseGOPFixture, filepath.Join(h.filesDir, "clip.mp4"))
	h.runWorker(t)
	whole := h.trimOK(t, "clip.mp4", 1800, 3500)
	stat, err := os.Stat(filepath.Join(h.filesDir, whole.RelPath))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(h.filesDir, whole.RelPath)); err != nil {
		t.Fatal(err)
	}
	if _, ok := h.upload(); !ok {
		t.Fatal("the first trim published no upload")
	}

	// Put the canceling namespace where the disk's is.
	id := vfs.FilesNamespace(testSerial)
	i := slices.IndexFunc(h.registry.List(""), func(ns vfs.Namespace) bool { return ns.ID == id })
	if i < 0 {
		t.Fatalf("no namespace %s registered", id)
	}
	ns := h.registry.List("")[i]
	disk, _ := h.registry.Get(id)
	var cancelCode atomic.Int64
	canceling := &cancelingVFS{VFS: disk, cancel: func(ctx context.Context) {
		req := httptest.NewRequest(http.MethodDelete, fmt.Sprintf("/api/v0/jobs/%d", jobutil.JobID(ctx)), nil)
		w := httptest.NewRecorder()
		h.engine.ServeHTTP(w, req)
		cancelCode.Store(int64(w.Code))
	}}
	h.registry.Unregister(id)
	if err := h.registry.Register(ns, canceling); err != nil {
		t.Fatal(err)
	}

	job := waitForJob(t, h.queue, acceptedJobID(t, h.trim(fmt.Sprintf(`{"relPath":"clip.mp4","serial":%q,"startMs":1800,"endMs":3500}`, testSerial))))
	if cancelCode.Load() != http.StatusOK {
		t.Fatalf("DELETE /jobs/{id} returned %d, want 200", cancelCode.Load())
	}
	if job.Status != jobutil.StatusCanceled || string(job.Detail) != "{}" {
		t.Fatalf("job = %s with detail %s, want canceled with none", job.Status, job.Detail)
	}
	if sent := canceling.sent.Load(); sent >= stat.Size() {
		t.Errorf("the trim sent %d bytes after it was canceled, the whole %d-byte clip", sent, stat.Size())
	}
	left, err := os.ReadDir(h.filesDir)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, e := range left {
		got = append(got, e.Name())
	}
	if !slices.Equal(got, []string{"clip.mp4"}) {
		t.Errorf("the folder holds %v after a canceled trim, want only clip.mp4", got)
	}
	if e, ok := h.upload(); ok {
		t.Errorf("a canceled trim published %+v", e)
	}
}
