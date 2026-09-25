package v0_users_test

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	v0_users "github.com/autobutler-org/quark/internal/server/api/v0/users"
	"github.com/autobutler-org/quark/pkg/util/avatarutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/gin-gonic/gin"
)

const callerID = 7

// secret stands in for a GPS position inside the upload's EXIF block.
const secret = "GPS-47.6205N-122.3493W"

type harness struct {
	engine  *gin.Engine
	events  <-chan eventbus.Event
	dataDir string
}

// newHarness mounts the users router the way routes.go does, as a signed-in
// caller, with HOME moved so the data directory is this test's own.
func newHarness(t *testing.T) harness {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	t.Cleanup(unsubscribe)
	deps := deputil.NewDependencies().WithEventBus(bus)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "userID", int64(callerID))
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_users.NewRouter())
	return harness{engine: engine, events: events, dataDir: storageutil.GetDataDir()}
}

func (h harness) do(req *http.Request) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

func (h harness) upload(t *testing.T, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	part, err := mw.CreateFormFile("file", "me.jpg")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(body); err != nil {
		t.Fatal(err)
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	req := httptest.NewRequest(http.MethodPut, "/api/v0/users/me/avatar", &buf)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	return h.do(req)
}

func (h harness) get(t *testing.T, etag string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, "/api/v0/users/7/avatar", nil)
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}
	return h.do(req)
}

func (h harness) expectAccountChanged(t *testing.T) {
	t.Helper()
	select {
	case e := <-h.events:
		if e.Kind != eventbus.EventAccountChanged {
			t.Fatalf("event = %q, want account_changed", e.Kind)
		}
	default:
		t.Fatal("no account_changed event published")
	}
}

func testImage(w, h int) image.Image {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			img.Set(x, y, color.RGBA{R: uint8(x), G: uint8(y), B: 128, A: 255})
		}
	}
	return img
}

// jpegWithExif encodes a JPEG and splices an APP1 Exif segment carrying
// secret in right after the SOI marker, where a camera writes it.
func jpegWithExif(t *testing.T, w, h int) []byte {
	t.Helper()
	var enc bytes.Buffer
	if err := jpeg.Encode(&enc, testImage(w, h), nil); err != nil {
		t.Fatal(err)
	}
	// A little-endian TIFF header and an IFD with no entries, then the secret.
	payload := append([]byte("Exif\x00\x00II*\x00\x08\x00\x00\x00\x00\x00\x00\x00\x00\x00"), secret...)
	segment := []byte{0xFF, 0xE1, 0, 0}
	binary.BigEndian.PutUint16(segment[2:], uint16(len(payload)+2))
	segment = append(segment, payload...)
	raw := enc.Bytes()
	return append(append(append([]byte{}, raw[:2]...), segment...), raw[2:]...)
}

func TestSetAvatar_StoresSquareWithoutExif(t *testing.T) {
	h := newHarness(t)
	upload := jpegWithExif(t, 640, 480)
	if !bytes.Contains(upload, []byte(secret)) {
		t.Fatal("test upload lost its EXIF")
	}

	w := h.upload(t, upload)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT = %d: %s", w.Code, w.Body.String())
	}
	var resp v0_users.SetAvatarResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil || resp.AvatarUpdatedAt == 0 {
		t.Fatalf("body %s: want avatarUpdatedAt, err %v", w.Body.String(), err)
	}
	h.expectAccountChanged(t)

	stored, err := os.ReadFile(filepath.Join(avatarutil.Dir(h.dataDir), "7.jpg"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(stored, []byte(secret)) || bytes.Contains(stored, []byte("Exif\x00")) {
		t.Error("stored picture still carries the upload's EXIF")
	}
	cfg, format, err := image.DecodeConfig(bytes.NewReader(stored))
	if err != nil || format != "jpeg" || cfg.Width != avatarutil.Size || cfg.Height != avatarutil.Size {
		t.Errorf("stored %s %dx%d (err %v), want jpeg 256x256", format, cfg.Width, cfg.Height, err)
	}

	got := h.get(t, "")
	if got.Code != http.StatusOK || got.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("GET = %d %q", got.Code, got.Header().Get("Content-Type"))
	}
	if !bytes.Equal(got.Body.Bytes(), stored) {
		t.Error("GET did not serve the stored file")
	}
	etag := got.Header().Get("ETag")
	if etag == "" {
		t.Fatal("GET sent no ETag")
	}
	if again := h.get(t, etag); again.Code != http.StatusNotModified {
		t.Errorf("GET with a matching If-None-Match = %d, want 304", again.Code)
	}
}

func TestSetAvatar_ReplaceSwapsFormat(t *testing.T) {
	h := newHarness(t)
	if w := h.upload(t, jpegWithExif(t, 300, 300)); w.Code != http.StatusOK {
		t.Fatalf("first PUT = %d", w.Code)
	}
	var pngBody bytes.Buffer
	if err := png.Encode(&pngBody, testImage(100, 400)); err != nil {
		t.Fatal(err)
	}
	if w := h.upload(t, pngBody.Bytes()); w.Code != http.StatusOK {
		t.Fatalf("second PUT = %d: %s", w.Code, w.Body.String())
	}

	dir := avatarutil.Dir(h.dataDir)
	if _, err := os.Stat(filepath.Join(dir, "7.jpg")); !os.IsNotExist(err) {
		t.Errorf("the replaced JPEG is still there (stat err %v)", err)
	}
	got := h.get(t, "")
	if got.Code != http.StatusOK || got.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("GET = %d %q, want 200 image/png", got.Code, got.Header().Get("Content-Type"))
	}
	cfg, err := png.DecodeConfig(got.Body)
	if err != nil || cfg.Width != avatarutil.Size || cfg.Height != avatarutil.Size {
		t.Errorf("served %dx%d (err %v), want 256x256", cfg.Width, cfg.Height, err)
	}
}

func TestDeleteAvatar(t *testing.T) {
	h := newHarness(t)
	if w := h.upload(t, jpegWithExif(t, 64, 64)); w.Code != http.StatusOK {
		t.Fatalf("PUT = %d", w.Code)
	}
	h.expectAccountChanged(t)

	del := h.do(httptest.NewRequest(http.MethodDelete, "/api/v0/users/me/avatar", nil))
	if del.Code != http.StatusNoContent {
		t.Fatalf("DELETE = %d: %s", del.Code, del.Body.String())
	}
	h.expectAccountChanged(t)
	if got := h.get(t, ""); got.Code != http.StatusNotFound {
		t.Errorf("GET after DELETE = %d, want 404", got.Code)
	}

	// Removing nothing succeeds and tells nobody.
	if again := h.do(httptest.NewRequest(http.MethodDelete, "/api/v0/users/me/avatar", nil)); again.Code != http.StatusNoContent {
		t.Errorf("second DELETE = %d, want 204", again.Code)
	}
	select {
	case e := <-h.events:
		t.Errorf("a no-op DELETE published %q", e.Kind)
	default:
	}
}

func TestSetAvatar_OversizeIs413(t *testing.T) {
	h := newHarness(t)
	if w := h.upload(t, jpegWithExif(t, 32, 32)); w.Code != http.StatusOK {
		t.Fatalf("PUT = %d", w.Code)
	}
	w := h.upload(t, make([]byte, avatarutil.MaxUploadBytes+1))
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("PUT of 10 MiB + 1 = %d, want 413", w.Code)
	}
	if got := h.get(t, ""); got.Code != http.StatusOK {
		t.Errorf("the previous picture should survive a refused upload, GET = %d", got.Code)
	}
	assertNoSpool(t, h.dataDir)
}

func TestSetAvatar_NonImageIs400(t *testing.T) {
	h := newHarness(t)
	w := h.upload(t, []byte("%PDF-1.7 not a picture"))
	if w.Code != http.StatusBadRequest {
		t.Fatalf("PUT of a PDF = %d, want 400", w.Code)
	}
	if got := h.get(t, ""); got.Code != http.StatusNotFound {
		t.Errorf("GET = %d, want 404", got.Code)
	}
	assertNoSpool(t, h.dataDir)
}

func TestSetAvatar_MissingFileFieldIs400(t *testing.T) {
	h := newHarness(t)
	req := httptest.NewRequest(http.MethodPut, "/api/v0/users/me/avatar", io.NopCloser(bytes.NewReader([]byte("x"))))
	if w := h.do(req); w.Code != http.StatusBadRequest {
		t.Errorf("PUT without multipart = %d, want 400", w.Code)
	}
}

func TestGetAvatar_BadID(t *testing.T) {
	h := newHarness(t)
	if w := h.do(httptest.NewRequest(http.MethodGet, "/api/v0/users/me/avatar", nil)); w.Code != http.StatusBadRequest {
		t.Errorf("GET /users/me/avatar = %d, want 400", w.Code)
	}
}

// assertNoSpool checks that a refused upload left no spooled copy behind.
func assertNoSpool(t *testing.T, dataDir string) {
	t.Helper()
	entries, err := os.ReadDir(avatarutil.Dir(dataDir))
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	for _, e := range entries {
		if filepath.Ext(e.Name()) != ".jpg" && filepath.Ext(e.Name()) != ".png" {
			t.Errorf("left behind %s", e.Name())
		}
	}
}
