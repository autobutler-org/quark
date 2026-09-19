package v0_videos_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_videos "github.com/autobutler-org/quark/internal/server/api/v0/videos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/transcodeutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/gin-gonic/gin"
)

const testSerial = "test-serial"

// fakeDetector reports one USB disk mounted at a temp directory. Requests carry
// its serial, so the handler never falls back to the real system files dir.
type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Disk", MountPoint: f.mountPoint, UsbInfo: fakeUsb{}}}, nil
}

// fakeUsb answers GetSerial, the only method a serial lookup calls. Any other
// call panics on the nil embedded interface, which points straight here.
type fakeUsb struct {
	storageutil.UsbDevice
}

func (fakeUsb) GetSerial() string { return testSerial }

type harness struct {
	engine   *gin.Engine
	filesDir string
	queue    *jobutil.Queue
	events   <-chan eventbus.Event
}

// newHarness mounts the videos router over a fake USB disk and a real temp
// database, with the transcode job kind registered as it is at boot. The
// worker is not started, so jobs stay pending unless a test calls runWorker.
func newHarness(t *testing.T) harness {
	t.Helper()
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	bus := eventbus.New()
	events, unsub := bus.Subscribe("videos-test")
	t.Cleanup(unsub)
	storage := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	database := dbtest.NewDB(t)
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database, EventBus: bus})
	queue.Register(jobutil.RegisterParams{
		Kind:    transcodeutil.Kind,
		Handler: transcodeutil.NewHandler(transcodeutil.NewHandlerParams{Storage: storage, Database: database, EventBus: bus}),
	})
	deps := deputil.NewDependencies().
		WithStorageService(storage).
		WithDatabase(database).
		WithEventBus(bus).
		WithJobQueue(queue)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_videos.NewRouter())
	return harness{engine: engine, filesDir: filesDir, queue: queue, events: events}
}

func (h harness) post(body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v0/videos/transcode", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

func (h harness) runWorker(t *testing.T) {
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
}

func (h harness) job(t *testing.T, id int64) jobutil.Job {
	t.Helper()
	res, err := h.queue.Get(context.Background(), jobutil.GetParams{ID: id})
	if err != nil {
		t.Fatal(err)
	}
	return res.Job
}

// writeClip generates a one-second H.264 test pattern clip, with no audio,
// with real ffmpeg.
func (h harness) writeClip(t *testing.T, rel string) {
	t.Helper()
	cmd := exec.Command("ffmpeg", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=size=64x48:rate=10:duration=1",
		"-c:v", "libx264", "-pix_fmt", "yuv420p", "-y", filepath.Join(h.filesDir, rel))
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("generate clip: %v\n%s", err, out)
	}
}

func transcodeBody(relPath, format, quality string) string {
	return fmt.Sprintf(`{"relPath":%q,"serial":%q,"format":%q,"quality":%q}`, relPath, testSerial, format, quality)
}

// acceptedJobID reads the jobId out of a 202 response.
func acceptedJobID(t *testing.T, w *httptest.ResponseRecorder) int64 {
	t.Helper()
	if w.Code != http.StatusAccepted {
		t.Fatalf("POST returned %d, want 202: %s", w.Code, w.Body.String())
	}
	var body struct {
		JobID int64 `json:"jobId"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil || body.JobID == 0 {
		t.Fatalf("POST body %s has no jobId: %v", w.Body.String(), err)
	}
	return body.JobID
}

func requireFFmpeg(t *testing.T) {
	t.Helper()
	if !videoutil.Available() {
		t.Skip("ffmpeg not available")
	}
}

func TestTranscodeVideoRejectsBadRequests(t *testing.T) {
	h := newHarness(t)
	if !videoutil.Available() {
		if w := h.post(transcodeBody("clip.mp4", "mov", "small")); w.Code != http.StatusNotImplemented {
			t.Fatalf("without ffmpeg POST returned %d, want 501", w.Code)
		}
		return
	}
	h.writeClip(t, "clip.mp4")
	if err := os.WriteFile(filepath.Join(h.filesDir, "notes.txt"), []byte("not a video"), 0o644); err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		name string
		body string
		want int
	}{
		{"malformed body", `{`, http.StatusBadRequest},
		{"missing relPath", transcodeBody("", "mov", "original"), http.StatusBadRequest},
		{"an old preset name instead of a format", transcodeBody("clip.mp4", "compatible", "original"), http.StatusBadRequest},
		{"unknown quality", transcodeBody("clip.mp4", "mov", "best"), http.StatusBadRequest},
		{"the source's own format at original quality", transcodeBody("clip.mp4", "mp4", "original"), http.StatusBadRequest},
		{"path traversal", transcodeBody("../../../../etc/passwd", "mov", "original"), http.StatusBadRequest},
		{"the files dir itself", transcodeBody(".", "mov", "original"), http.StatusBadRequest},
		{"missing source", transcodeBody("gone.mp4", "mov", "original"), http.StatusNotFound},
		{"source that is not a video", transcodeBody("notes.txt", "mov", "original"), http.StatusNotFound},
	}
	available, err := videoutil.AvailableFormats()
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range videoutil.Formats() {
		if !slices.Contains(available, f) {
			cases = append(cases, struct {
				name string
				body string
				want int
			}{"a format this ffmpeg cannot write", transcodeBody("clip.mp4", string(f), "original"), http.StatusBadRequest})
			break
		}
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if w := h.post(c.body); w.Code != c.want {
				t.Fatalf("POST returned %d, want %d: %s", w.Code, c.want, w.Body.String())
			}
		})
	}
	list, err := h.queue.List(context.Background(), jobutil.ListParams{Kinds: []string{transcodeutil.Kind}})
	if err != nil {
		t.Fatal(err)
	}
	if len(list.Jobs) != 0 {
		t.Fatalf("rejected requests queued %d job(s)", len(list.Jobs))
	}
}

func TestTranscodeVideoQueuesAJobInTheRightLane(t *testing.T) {
	requireFFmpeg(t)
	h := newHarness(t)
	h.writeClip(t, "clip.mp4")

	cases := []struct {
		name     string
		body     string
		wantName string
		wantLane string
		want     transcodeutil.Params
	}{
		{
			name:     "H.264 into MOV at original quality copies",
			body:     transcodeBody("clip.mp4", "mov", "original"),
			wantName: "Convert clip.mp4 to MOV",
			wantLane: transcodeutil.LaneCopy,
			want:     transcodeutil.Params{RelPath: "clip.mp4", Serial: testSerial, Format: "mov", Quality: videoutil.QualityOriginal},
		},
		{
			name:     "small always re-encodes, even into its own format",
			body:     transcodeBody("clip.mp4", "mp4", "small"),
			wantName: "Convert clip.mp4 to MP4 (small)",
			wantLane: transcodeutil.LaneEncode,
			want:     transcodeutil.Params{RelPath: "clip.mp4", Serial: testSerial, Format: "mp4", Quality: videoutil.QualitySmall},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			job := h.job(t, acceptedJobID(t, h.post(c.body)))
			if job.Kind != transcodeutil.Kind || job.Name != c.wantName || job.Lane != c.wantLane || job.Status != jobutil.StatusPending {
				t.Errorf("queued job = %+v, want %q in lane %s", job, c.wantName, c.wantLane)
			}
			var params transcodeutil.Params
			if err := json.Unmarshal(job.Params, &params); err != nil || params != c.want {
				t.Errorf("queued job params = %s (%v), want %+v", job.Params, err, c.want)
			}
		})
	}
}

func TestTranscodeRunsToCompletion(t *testing.T) {
	requireFFmpeg(t)
	h := newHarness(t)
	h.runWorker(t)
	h.writeClip(t, "clip.mov")

	id := acceptedJobID(t, h.post(transcodeBody("clip.mov", "mkv", "original")))

	deadline := time.Now().Add(30 * time.Second)
	for job := h.job(t, id); job.Status != jobutil.StatusCompleted; job = h.job(t, id) {
		if job.Status == jobutil.StatusFailed || job.Status == jobutil.StatusCanceled {
			t.Fatalf("job ended %s: %s", job.Status, job.Error)
		}
		if time.Now().After(deadline) {
			t.Fatalf("job did not complete: %+v", job)
		}
		time.Sleep(20 * time.Millisecond)
	}

	if _, err := videoutil.Probe(context.Background(), filepath.Join(h.filesDir, "clip.mkv")); err != nil {
		t.Errorf("output is not a readable video: %v", err)
	}

	// Open file browsers refresh on the upload event for the output file.
	timeout := time.After(5 * time.Second)
	for {
		select {
		case e := <-h.events:
			if e.Kind == eventbus.EventUpload {
				if e.Path != "clip.mkv" || e.DeviceSerial != testSerial {
					t.Errorf("upload event = %+v", e)
				}
				return
			}
		case <-timeout:
			t.Fatal("no upload event for the output file")
		}
	}
}

func TestListTranscodeFormats(t *testing.T) {
	h := newHarness(t)
	req := httptest.NewRequest(http.MethodGet, "/api/v0/videos/transcode/formats", nil)
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	if !videoutil.Available() {
		if w.Code != http.StatusNotImplemented {
			t.Fatalf("without ffmpeg GET returned %d, want 501", w.Code)
		}
		return
	}
	if w.Code != http.StatusOK {
		t.Fatalf("GET returned %d, want 200: %s", w.Code, w.Body.String())
	}
	var body struct {
		Formats []struct {
			Format string `json:"format"`
			Label  string `json:"label"`
		} `json:"formats"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil || body.Formats == nil {
		t.Fatalf("GET body %s is not a formats list: %v", w.Body.String(), err)
	}
	available, err := videoutil.AvailableFormats()
	if err != nil {
		t.Fatal(err)
	}
	if len(body.Formats) != len(available) {
		t.Fatalf("GET listed %d formats, want the %d this ffmpeg writes: %s", len(body.Formats), len(available), w.Body.String())
	}
	for i, f := range available {
		if body.Formats[i].Format != string(f) || body.Formats[i].Label != f.Label() {
			t.Errorf("format %d = %+v, want %s labeled %s", i, body.Formats[i], f, f.Label())
		}
	}
}
