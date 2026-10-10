package v0_files_test

import (
	"context"
	"crypto/rand"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	v0_files "github.com/autobutler-org/quark/internal/server/api/v0/files"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/downloadutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// stalledClient is a client that stops reading after the first piece of the
// archive arrives: its writes block until the request is canceled.
type stalledClient struct {
	*httptest.ResponseRecorder
	ctx     context.Context
	started chan struct{}
	once    sync.Once
}

func (w *stalledClient) Write(p []byte) (int, error) {
	w.once.Do(func() { close(w.started) })
	<-w.ctx.Done()
	return 0, errors.New("connection reset by peer")
}

// zipLimitTargets are the devices a folder download is limited on alike: the
// internal drive and a USB drive, each through its own namespace (#2642).
var zipLimitTargets = map[string]string{"internal": "", "device": testUsbSerial}

// zipURL downloads the "big" folder from the device serial names.
func zipURL(serial string) string {
	url := "/api/v0/files/download?filePath=big"
	if serial != "" {
		url += "&serial=" + serial
	}
	return url
}

// newZipLimitEngine serves downloads with one zip slot and a short wait, with
// the "big" folder on the device serial names.
func newZipLimitEngine(t *testing.T, serial string) (*gin.Engine, *downloadutil.ZipSlots) {
	t.Helper()
	deps, internalDir, usbDir := newDeviceUploadDeps(t)
	filesDir := internalDir
	if serial != "" {
		filesDir = usbDir
	}
	slots := downloadutil.NewZipSlots(downloadutil.ZipSlotsParams{Slots: 1, Wait: 50 * time.Millisecond})
	deps.WithZipSlots(slots)

	dir := filepath.Join(filesDir, "big")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	// Larger than the zip writer's buffer, so the archive reaches the client
	// before it is finished.
	content := make([]byte, 64<<10)
	_, _ = rand.Read(content)
	if err := os.WriteFile(filepath.Join(dir, "a.bin"), content, 0o644); err != nil {
		t.Fatal(err)
	}

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_files.NewRouter())
	return engine, slots
}

// startStalledZip starts a folder download whose client stops reading, and
// returns once the zip holds its slot. Canceling the returned func ends it.
func startStalledZip(t *testing.T, engine *gin.Engine, url string) (cancel func(), done <-chan struct{}) {
	t.Helper()
	ctx, cancelCtx := context.WithCancel(context.Background())
	w := &stalledClient{ResponseRecorder: httptest.NewRecorder(), ctx: ctx, started: make(chan struct{})}
	finished := make(chan struct{})
	go func() {
		defer close(finished)
		req := httptest.NewRequest(http.MethodGet, url, nil).WithContext(ctx)
		engine.ServeHTTP(w, req)
	}()
	select {
	case <-w.started:
	case <-time.After(5 * time.Second):
		cancelCtx()
		t.Fatal("the first zip never started streaming")
	}
	return cancelCtx, finished
}

// With every zip slot held by a download in progress, the next folder
// download is turned away with 503 and a Retry-After rather than starting a
// second deflate on a busy board (#2757).
func TestDownloadFolder_BusyZipSlotsAnswer503(t *testing.T) {
	for name, serial := range zipLimitTargets {
		t.Run(name, func(t *testing.T) {
			engine, _ := newZipLimitEngine(t, serial)
			cancel, done := startStalledZip(t, engine, zipURL(serial))
			defer func() { cancel(); <-done }()

			w := httptest.NewRecorder()
			engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, zipURL(serial), nil))
			if w.Code != http.StatusServiceUnavailable {
				t.Fatalf("status: got %d, want 503", w.Code)
			}
			if got := w.Header().Get("Retry-After"); got != downloadutil.ZipRetryAfter {
				t.Errorf("Retry-After: got %q, want %q", got, downloadutil.ZipRetryAfter)
			}
			if got := w.Header().Get("Content-Disposition"); got != "" {
				t.Errorf("Content-Disposition on a 503: %q", got)
			}
		})
	}
}

// A download whose client goes away gives its slot back, so the next one
// runs.
func TestDownloadFolder_CanceledZipReleasesItsSlot(t *testing.T) {
	for name, serial := range zipLimitTargets {
		t.Run(name, func(t *testing.T) {
			engine, slots := newZipLimitEngine(t, serial)
			cancel, done := startStalledZip(t, engine, zipURL(serial))
			if slots.Available() != 0 {
				t.Fatalf("Available() = %d while zipping, want 0", slots.Available())
			}
			cancel()
			<-done
			if slots.Available() != 1 {
				t.Fatalf("Available() = %d after the client left, want 1", slots.Available())
			}

			w := httptest.NewRecorder()
			engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, zipURL(serial), nil))
			if w.Code != http.StatusOK {
				t.Fatalf("status after release: got %d, want 200", w.Code)
			}
		})
	}
}
