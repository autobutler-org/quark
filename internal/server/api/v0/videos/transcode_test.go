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
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_jobs "github.com/autobutler-org/quark/internal/server/api/v0/jobs"
	v0_videos "github.com/autobutler-org/quark/internal/server/api/v0/videos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/transcodeutil"
	"github.com/autobutler-org/quark/pkg/util/trimutil"
	"github.com/autobutler-org/quark/pkg/util/videoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
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
	// dataDir is the disk's data dir, whose tmp area stages conversions.
	dataDir  string
	registry vfs.Registry
	database *db.DatabaseSqlc
	queue    *jobutil.Queue
	events   <-chan eventbus.Event
	// principal is who every request acts as: the system unless a test
	// changes it.
	principal *accessutil.Principal
}

// newHarness mounts the videos router over a fake USB disk and a real temp
// database, with the transcode and trim job kinds registered as they are at
// boot. The
// worker is not started, so jobs stay pending unless a test calls runWorker.
func newHarness(t *testing.T) harness {
	t.Helper()
	return newHarnessWithRemux(t, nil)
}

// newHarnessWithRemux is newHarness with the jobs router mounted beside the
// videos one and remux doing the conversions; nil is the real remux.
func newHarnessWithRemux(t *testing.T, remux transcodeutil.RemuxFunc) harness {
	t.Helper()
	// Anything that falls back to the system data dir lands in a temp HOME.
	t.Setenv("HOME", t.TempDir())
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	bus := eventbus.New()
	events, unsub := bus.Subscribe("videos-test")
	t.Cleanup(unsub)
	storage := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	// The disk's namespace, as the server registers it on mount (#2639).
	registry := vfs.NewRegistry()
	if _, err := vfs.SyncDeviceNamespaces(vfs.SyncDeviceNamespacesParams{Registry: registry, Storage: storage}); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	queue := jobutil.NewQueue(jobutil.NewQueueParams{Database: database, EventBus: bus})
	queue.Register(jobutil.RegisterParams{
		Kind: transcodeutil.Kind,
		Handler: transcodeutil.NewHandler(transcodeutil.NewHandlerParams{
			Storage: storage, Registry: registry, Database: database, EventBus: bus, Remux: remux,
		}),
	})
	queue.Register(jobutil.RegisterParams{
		Kind: trimutil.Kind,
		Handler: trimutil.NewHandler(trimutil.NewHandlerParams{
			Storage: storage, Registry: registry, Database: database, EventBus: bus,
		}),
	})
	deps := deputil.NewDependencies().
		WithStorageService(storage).
		WithVFSRegistry(registry).
		WithDatabase(database).
		WithEventBus(bus).
		WithJobQueue(queue)

	system := accessutil.System
	principal := &system

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", *principal)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_videos.NewRouter())
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_jobs.NewRouter())
	return harness{
		engine: engine, filesDir: filesDir, dataDir: filepath.Dir(filesDir), registry: registry,
		database: database, queue: queue, events: events, principal: principal,
	}
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
	startQueue(t, h.queue)
}

func (h harness) job(t *testing.T, id int64) jobutil.Job {
	t.Helper()
	res, err := h.queue.Get(context.Background(), jobutil.GetParams{ID: id})
	if err != nil {
		t.Fatal(err)
	}
	return res.Job
}

// The clips are videoutil's test fixtures, copied from sprocket's corpus:
// three seconds of H.264 and AAC at 128x72, keyframes every half second, and
// an MPEG-TS copy of the same streams.
const (
	gopFixture = "../../../../../pkg/util/videoutil/testdata/h264-gop12.mp4"
	tsFixture  = "../../../../../pkg/util/videoutil/testdata/h264-aac.ts"
)

// copyFixture copies the fixture at src to dst, making dst's folder.
func copyFixture(t *testing.T, src, dst string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		t.Fatal(err)
	}
	in, err := os.Open(src)
	if err != nil {
		t.Fatal(err)
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		t.Fatal(err)
	}
	defer out.Close()
	if _, err := io.Copy(out, in); err != nil {
		t.Fatal(err)
	}
}

// writeClip puts the H.264 and AAC fixture at rel.
func (h harness) writeClip(t *testing.T, rel string) {
	t.Helper()
	copyFixture(t, gopFixture, filepath.Join(h.filesDir, rel))
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

func TestTranscodeVideoRejectsBadRequests(t *testing.T) {
	h := newHarness(t)
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
		{"missing relPath", transcodeBody("", "mkv", "original"), http.StatusBadRequest},
		{"an old preset name instead of a format", transcodeBody("clip.mp4", "compatible", "original"), http.StatusBadRequest},
		{"small quality, which needed a re-encode", transcodeBody("clip.mp4", "mkv", "small"), http.StatusBadRequest},
		{"the source's own format", transcodeBody("clip.mp4", "mp4", "original"), http.StatusBadRequest},
		{"a format sprocket does not write", transcodeBody("clip.mp4", "avi", "original"), http.StatusBadRequest},
		{"a format that cannot hold the codecs", transcodeBody("clip.mp4", "webm", "original"), http.StatusBadRequest},
		{"path traversal", transcodeBody("../../../../etc/passwd", "mkv", "original"), http.StatusBadRequest},
		{"the files dir itself", transcodeBody(".", "mkv", "original"), http.StatusBadRequest},
		{"missing source", transcodeBody("gone.mp4", "mkv", "original"), http.StatusNotFound},
		{"source that is not a video", transcodeBody("notes.txt", "mkv", "original"), http.StatusUnprocessableEntity},
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

func TestTranscodeVideoQueuesARemux(t *testing.T) {
	h := newHarness(t)
	h.writeClip(t, "clip.mp4")

	cases := []struct {
		name string
		body string
		want transcodeutil.Params
	}{
		{"original quality", transcodeBody("clip.mp4", "mkv", "original"), transcodeutil.Params{RelPath: "clip.mp4", Serial: testSerial, Format: "mkv", Quality: "original"}},
		{"no quality", fmt.Sprintf(`{"relPath":"clip.mp4","serial":%q,"format":"mkv"}`, testSerial), transcodeutil.Params{RelPath: "clip.mp4", Serial: testSerial, Format: "mkv"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			job := h.job(t, acceptedJobID(t, h.post(c.body)))
			if job.Kind != transcodeutil.Kind || job.Name != "Convert clip.mp4 to MKV" || job.Lane != transcodeutil.LaneCopy || job.Status != jobutil.StatusPending {
				t.Errorf("queued job = %+v, want a pending remux into MKV in the copy lane", job)
			}
			var params transcodeutil.Params
			if err := json.Unmarshal(job.Params, &params); err != nil || params != c.want {
				t.Errorf("queued job params = %s (%v), want %+v", job.Params, err, c.want)
			}
		})
	}
}

// get sends a GET and returns the recorder.
func (h harness) get(path string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	return w
}

func TestListTranscodeFormats(t *testing.T) {
	h := newHarness(t)
	h.writeClip(t, "clip.mp4")
	copyFixture(t, tsFixture, filepath.Join(h.filesDir, "clip.ts"))

	cases := []struct {
		name  string
		query string
		want  []string
	}{
		{"every format the device writes", "", []string{"mp4", "mov", "mkv", "webm", "m4v", "3gp", "3g2", "ts"}},
		{"what an H.264 and AAC mp4 fits", "?relPath=clip.mp4&serial=" + testSerial, []string{"mov", "mkv", "m4v", "3gp", "3g2", "ts"}},
		{"what a transport stream remuxes into", "?relPath=clip.ts&serial=" + testSerial, []string{"mp4", "mov", "m4v", "3gp", "3g2"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			w := h.get("/api/v0/videos/transcode/formats" + c.query)
			if w.Code != http.StatusOK {
				t.Fatalf("GET returned %d, want 200: %s", w.Code, w.Body.String())
			}
			var body struct {
				Formats []struct {
					Format string `json:"format"`
					Label  string `json:"label"`
				} `json:"formats"`
			}
			if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
				t.Fatalf("GET body %s is not a formats list: %v", w.Body.String(), err)
			}
			got := make([]string, 0, len(body.Formats))
			for _, f := range body.Formats {
				got = append(got, f.Format)
				if f.Label != videoutil.Format(f.Format).Label() {
					t.Errorf("%s is labeled %q, want %q", f.Format, f.Label, videoutil.Format(f.Format).Label())
				}
			}
			if !slices.Equal(got, c.want) {
				t.Fatalf("GET listed %v, want %v", got, c.want)
			}
		})
	}
	for _, rel := range []string{"gone.mp4", "../../../../etc/passwd"} {
		if w := h.get("/api/v0/videos/transcode/formats?relPath=" + rel + "&serial=" + testSerial); w.Code != http.StatusNotFound && w.Code != http.StatusBadRequest {
			t.Errorf("formats for %s returned %d, want 404 or 400", rel, w.Code)
		}
	}
}

func (h harness) trim(body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/api/v0/videos/trim", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

func TestTrimVideo(t *testing.T) {
	h := newHarness(t)
	h.writeClip(t, "clip.mp4")
	h.writeClip(t, "phone.MOV")
	copyFixture(t, tsFixture, filepath.Join(h.filesDir, "clip.ts"))
	h.runWorker(t)

	cases := []struct {
		name      string
		source    string
		wantPath  string
		wantStart int64
	}{
		{"starts where it was asked, between keyframes", "clip.mp4", "clip_trimmed.mp4", 1200},
		{"a MOV stays a MOV", "phone.MOV", "phone_trimmed.MOV", 1200},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			body := h.trimOK(t, c.source, 1200, 2200)
			if body.RelPath != c.wantPath || body.ActualStartMs != c.wantStart {
				t.Fatalf("trim = %+v, want %s starting at %dms", body, c.wantPath, c.wantStart)
			}
			if _, err := videoutil.Probe(context.Background(), filepath.Join(h.filesDir, body.RelPath)); err != nil {
				t.Errorf("the clip is not a readable video: %v", err)
			}
			// Open file browsers refresh on this, so the clip is listed
			// without waiting for the next refresh interval.
			if e, ok := h.upload(); !ok || e.Path != c.wantPath || e.DeviceSerial != testSerial {
				t.Errorf("event = %+v (found %v), want an upload of %s on %s", e, ok, c.wantPath, testSerial)
			}
		})
	}

	// The client picks endMs from its player's duration, which can land a
	// millisecond past the server's probe of the same file (#2385): an end at
	// or past the end of the video means "to the end". The fixture is 3s long.
	for _, endMs := range []int64{3000, 3001, 60000} {
		t.Run(fmt.Sprintf("an end of %dms runs to the end", endMs), func(t *testing.T) {
			h.trimOK(t, "clip.mp4", 1200, endMs)
		})
	}

	for name, body := range map[string]string{
		"a start at the end of the video": `{"relPath":"clip.mp4","serial":%q,"startMs":3000,"endMs":3500}`,
		"a negative start":                `{"relPath":"clip.mp4","serial":%q,"startMs":-1,"endMs":3500}`,
		"an end before the start":         `{"relPath":"clip.mp4","serial":%q,"startMs":2000,"endMs":1000}`,
		"no relPath":                      `{"relPath":"","serial":%q,"startMs":0,"endMs":1000}`,
		"the device root":                 `{"relPath":"/","serial":%q,"startMs":0,"endMs":1000}`,
	} {
		t.Run(name+" is a 400", func(t *testing.T) {
			if w := h.trim(fmt.Sprintf(body, testSerial)); w.Code != http.StatusBadRequest {
				t.Fatalf("trim returned %d, want 400: %s", w.Code, w.Body.String())
			}
		})
	}

	t.Run("a transport stream fails its job and leaves nothing behind", func(t *testing.T) {
		job := waitForJob(t, h.queue, acceptedJobID(t, h.trim(fmt.Sprintf(`{"relPath":"clip.ts","serial":%q,"startMs":0,"endMs":1000}`, testSerial))))
		if job.Status != jobutil.StatusFailed || !strings.Contains(job.Error, "MPEG-TS") {
			t.Fatalf("job = %s %q, want failed naming MPEG-TS", job.Status, job.Error)
		}
		if _, err := os.Stat(filepath.Join(h.filesDir, "clip_trimmed.ts")); !os.IsNotExist(err) {
			t.Errorf("a refused trim left a file: %v", err)
		}
	})
}

func TestGetMetadata(t *testing.T) {
	h := newHarness(t)
	h.writeClip(t, "clip.mp4")
	w := h.get("/api/v0/videos/metadata?relPath=clip.mp4&serial=" + testSerial)
	if w.Code != http.StatusOK {
		t.Fatalf("GET returned %d, want 200: %s", w.Code, w.Body.String())
	}
	var body v0_videos.VideoMetadataJSON
	if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Duration != 3 || body.Width != 128 || body.Height != 72 || body.VideoCodec != "h264" ||
		body.AudioCodec != "aac" || body.Framerate != 24 || body.Rotation != 0 || body.Bitrate <= 0 {
		t.Fatalf("metadata = %+v, want 3s of 128x72 h264 and aac at 24 fps", body)
	}
}

// TestAnUnattachedDeviceIsNotFound names a serial no attached device has. Every
// route answers 404 and leaves the internal drive alone, though it holds a
// video at the same path: the serial has no namespace, and nothing falls back
// to another one.
func TestAnUnattachedDeviceIsNotFound(t *testing.T) {
	h := newHarness(t)
	internal := vfs.NewMemVFS(vfs.FilesNamespace(""))
	clip, err := os.Open(gopFixture)
	if err != nil {
		t.Fatal(err)
	}
	defer clip.Close()
	if err := internal.Write(context.Background(), "clip.mp4", clip, vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := h.registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, internal); err != nil {
		t.Fatal(err)
	}

	const gone = "unplugged"
	for name, w := range map[string]*httptest.ResponseRecorder{
		"metadata":  h.get("/api/v0/videos/metadata?relPath=clip.mp4&serial=" + gone),
		"formats":   h.get("/api/v0/videos/transcode/formats?relPath=clip.mp4&serial=" + gone),
		"trim":      h.trim(fmt.Sprintf(`{"relPath":"clip.mp4","serial":%q,"startMs":0,"endMs":1000}`, gone)),
		"transcode": h.post(fmt.Sprintf(`{"relPath":"clip.mp4","serial":%q,"format":"mkv"}`, gone)),
	} {
		if w.Code != http.StatusNotFound {
			t.Errorf("%s returned %d, want 404: %s", name, w.Code, w.Body.String())
		}
	}
	list, err := internal.List(context.Background(), "", nil)
	if err != nil || len(list) != 1 {
		t.Fatalf("the internal drive holds %v (%v), want only clip.mp4", list, err)
	}
}

// TestTrimNeverReplacesAFile trims a clip whose name, and its first numbered
// name, are taken: both keep their bytes and the clip takes the next name.
func TestTrimNeverReplacesAFile(t *testing.T) {
	h := newHarness(t)
	h.writeClip(t, "clip.mp4")
	for _, name := range []string{"clip_trimmed.mp4", "clip_trimmed_(1).mp4"} {
		if err := os.WriteFile(filepath.Join(h.filesDir, name), []byte("mine"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	h.runWorker(t)
	if got := h.trimOK(t, "clip.mp4", 0, 1000).RelPath; got != "clip_trimmed_(2).mp4" {
		t.Fatalf("the clip landed at %q, want clip_trimmed_(2).mp4", got)
	}
	for _, name := range []string{"clip_trimmed.mp4", "clip_trimmed_(1).mp4"} {
		if got, _ := os.ReadFile(filepath.Join(h.filesDir, name)); string(got) != "mine" {
			t.Errorf("%s holds %q, want it untouched", name, got)
		}
	}
}

// TestAnUnreadableVideoIs422 asks every route about a file that is there but
// does not read as a video: one that is not a video at all, and one cut short.
// Each answers 422 saying the video can't be read, never the 404 a missing
// file gets or a 500 (#3417).
func TestAnUnreadableVideoIs422(t *testing.T) {
	h := newHarness(t)
	if err := os.WriteFile(filepath.Join(h.filesDir, "notes.mp4"), []byte("not a video"), 0o644); err != nil {
		t.Fatal(err)
	}
	clip, err := os.ReadFile(gopFixture)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(h.filesDir, "cut-short.mp4"), clip[:len(clip)/2], 0o644); err != nil {
		t.Fatal(err)
	}

	for _, rel := range []string{"notes.mp4", "cut-short.mp4"} {
		for name, w := range map[string]*httptest.ResponseRecorder{
			"metadata":  h.get("/api/v0/videos/metadata?relPath=" + rel + "&serial=" + testSerial),
			"formats":   h.get("/api/v0/videos/transcode/formats?relPath=" + rel + "&serial=" + testSerial),
			"trim":      h.trim(fmt.Sprintf(`{"relPath":%q,"serial":%q,"startMs":0,"endMs":1000}`, rel, testSerial)),
			"transcode": h.post(transcodeBody(rel, "mkv", "original")),
		} {
			if w.Code != http.StatusUnprocessableEntity || !strings.Contains(w.Body.String(), "can't read this video") {
				t.Errorf("%s of %s returned %d %s, want a 422 saying the video can't be read", name, rel, w.Code, w.Body.String())
			}
		}
	}
}

// TestTranscodeEnqueueFailureIsLoggedAndNamed breaks the job store, as a
// read-only database does on a device (#3422): the POST answers 500 with the
// cause in its body.
func TestTranscodeEnqueueFailureIsLoggedAndNamed(t *testing.T) {
	h := newHarness(t)
	h.writeClip(t, "clip.mp4")
	if _, err := h.database.Db.Exec("DROP TABLE jobs"); err != nil {
		t.Fatal(err)
	}

	w := h.post(transcodeBody("clip.mp4", "mkv", "original"))
	if w.Code != http.StatusInternalServerError || !strings.Contains(w.Body.String(), "couldn't queue the conversion") ||
		!strings.Contains(w.Body.String(), "create job") {
		t.Fatalf("POST returned %d %s, want a 500 naming the failed job insert", w.Code, w.Body.String())
	}
}
