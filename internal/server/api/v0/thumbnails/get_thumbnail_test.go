package v0_thumbnails_test

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"hash/crc32"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_thumbnails "github.com/autobutler-org/quark/internal/server/api/v0/thumbnails"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// fakeDetector reports one internal device mounted at a temp directory.
type fakeDetector struct {
	mountPoint string
}

func (f *fakeDetector) DetectDevices() ([]storageutil.Device, error) {
	return []storageutil.Device{{Name: "Test Device", MountPoint: f.mountPoint, IsInternal: true}}, nil
}

// newThumbnailEngine builds the thumbnails router over a temp HOME, so the
// thumbnail cache and default files directory stay inside the test. With
// withVFS the files namespace is a LocalVFS; without it, the storage
// service's namespace the server registers. It returns the directory files go in and the
// database.
func newThumbnailEngine(t *testing.T, withVFS bool) (*gin.Engine, string, *db.DatabaseSqlc) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())

	mountPoint := t.TempDir()
	database := dbtest.NewDB(t)
	svc := storageutil.NewStorageService(&fakeDetector{mountPoint: mountPoint})
	deps := deputil.NewDependencies().WithDatabase(database).WithStorageService(svc)

	dir, err := storageutil.GetFilesDirForDevice(mountPoint)
	if err != nil {
		t.Fatalf("GetFilesDirForDevice: %v", err)
	}
	var files vfs.VFS = vfs.NewStorageServiceVFS(svc, vfs.FilesNamespace(""))
	if withVFS {
		dir = t.TempDir()
		if files, err = vfs.NewLocalVFS(dir, vfs.FilesNamespace("")); err != nil {
			t.Fatalf("NewLocalVFS: %v", err)
		}
	}
	reg := vfs.NewRegistry()
	if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, files); err != nil {
		t.Fatalf("Register: %v", err)
	}
	deps = deps.WithVFSRegistry(reg)

	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		// These tests are about serving, not access, so they act as an admin
		// (#1904). access_integration_test.go covers a non-admin.
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_thumbnails.NewRouter())
	return engine, dir, database
}

// pngBytes encodes a small image as PNG.
func pngBytes(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 32, 32))
	img.Set(3, 3, color.RGBA{R: 255, A: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("png.Encode: %v", err)
	}
	return buf.Bytes()
}

// writeZipWithPNG writes photos.zip into dir holding pics/red.png.
func writeZipWithPNG(t *testing.T, dir string) {
	t.Helper()
	var archive bytes.Buffer
	zw := zip.NewWriter(&archive)
	w, err := zw.Create("pics/red.png")
	if err != nil {
		t.Fatalf("zip Create: %v", err)
	}
	if _, err := w.Write(pngBytes(t)); err != nil {
		t.Fatalf("zip Write: %v", err)
	}
	if err := zw.Close(); err != nil {
		t.Fatalf("zip Close: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "photos.zip"), archive.Bytes(), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
}

func get(engine *gin.Engine, path string) *httptest.ResponseRecorder {
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
	return w
}

// expectSmallPNG fails unless w is a 96x96 PNG thumbnail.
func expectSmallPNG(t *testing.T, w *httptest.ResponseRecorder) {
	t.Helper()
	if w.Code != http.StatusOK {
		t.Fatalf("got %d: %s", w.Code, w.Body.String())
	}
	if ct := w.Header().Get("Content-Type"); ct != "image/png" {
		t.Errorf("Content-Type: got %q, want image/png", ct)
	}
	cfg, err := png.DecodeConfig(w.Body)
	if err != nil {
		t.Fatalf("body is not a PNG: %v", err)
	}
	if cfg.Width != 96 || cfg.Height != 96 {
		t.Errorf("thumbnail size: got %dx%d, want 96x96", cfg.Width, cfg.Height)
	}
}

// TestGetThumbnail_ArchiveEntry covers the file browser inside a zip: it asks
// for /thumbnails/<archive>/<entry>, which used to 500 because stat-ing a path
// through a regular file fails with ENOTDIR rather than ENOENT.
func TestGetThumbnail_ArchiveEntry(t *testing.T) {
	for name, withVFS := range map[string]bool{"vfs": true, "storage": false} {
		t.Run(name, func(t *testing.T) {
			engine, dir, database := newThumbnailEngine(t, withVFS)
			writeZipWithPNG(t, dir)

			expectSmallPNG(t, get(engine, "/api/v0/thumbnails/photos.zip/pics/red.png?size=sm"))
			// The second request is answered from the cache entry the first wrote.
			expectSmallPNG(t, get(engine, "/api/v0/thumbnails/photos.zip/pics/red.png?size=sm"))

			// The client shows the file icon for all of these.
			for _, path := range []string{
				"/api/v0/thumbnails/photos.zip/pics/missing.png?size=sm",
				"/api/v0/thumbnails/photos.zip/pics/camera.dng?size=sm",
				"/api/v0/thumbnails/photos.zip/pics/clip.mp4?size=sm",
			} {
				if w := get(engine, path); w.Code != http.StatusNotFound {
					t.Errorf("%s: got %d, want 404: %s", path, w.Code, w.Body.String())
				}
			}

			// An archive entry is not a library photo: it gets no hashes.
			if rows, err := database.Queries.ListNearDuplicates(context.Background()); err != nil || len(rows) != 0 {
				t.Errorf("archive entry hashed: %+v, %v", rows, err)
			}
		})
	}
}

// TestGetThumbnail_StoresPhotoHashes: internal-drive photos take the VFS
// path, which used to store no hash, so duplicate detection saw none of them
// (#1666). Both routes now store the dHash and the file's SHA-256, keyed by
// the canonical path.
func TestGetThumbnail_StoresPhotoHashes(t *testing.T) {
	for name, withVFS := range map[string]bool{"vfs": true, "storage": false} {
		t.Run(name, func(t *testing.T) {
			engine, dir, database := newThumbnailEngine(t, withVFS)
			data := pngBytes(t)
			if err := os.MkdirAll(filepath.Join(dir, "trip"), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, "trip", "red.png"), data, 0o644); err != nil {
				t.Fatal(err)
			}

			expectSmallPNG(t, get(engine, "/api/v0/thumbnails/trip/red.png?size=sm"))

			rows, err := database.Queries.ListNearDuplicates(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			sum := sha256.Sum256(data)
			if len(rows) != 1 || rows[0].RelPath != "trip/red.png" ||
				rows[0].ContentHash.String != hex.EncodeToString(sum[:]) {
				t.Fatalf("rows = %+v, want trip/red.png with its SHA-256", rows)
			}
		})
	}
}

// TestGetThumbnail_FolderNamedLikeArchive: a folder called album.zip is still a
// folder, and the images in it get ordinary thumbnails.
func TestGetThumbnail_FolderNamedLikeArchive(t *testing.T) {
	engine, dir, _ := newThumbnailEngine(t, true)
	if err := os.MkdirAll(filepath.Join(dir, "album.zip"), 0755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := os.WriteFile(filepath.Join(dir, "album.zip", "red.png"), pngBytes(t), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	expectSmallPNG(t, get(engine, "/api/v0/thumbnails/album.zip/red.png?size=sm"))
}

// TestGetThumbnail_PathThroughFileIsNotFound: a path that treats a regular
// file as a folder is a missing file, not a server error.
func TestGetThumbnail_PathThroughFileIsNotFound(t *testing.T) {
	engine, _, _ := newThumbnailEngine(t, false)
	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		t.Fatalf("GetFilesDir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "notes.txt"), []byte("hi"), 0644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}

	if w := get(engine, "/api/v0/thumbnails/notes.txt/pic.jpg?size=sm"); w.Code != http.StatusNotFound {
		t.Errorf("got %d, want 404: %s", w.Code, w.Body.String())
	}
}

// oversizePNGHeader is a PNG signature and an IHDR claiming 9000 × 9000 8-bit
// grayscale, 81 MP: all a decoder reads before sizing its pixel buffer.
func oversizePNGHeader() []byte {
	var data bytes.Buffer
	data.WriteString("\x89PNG\r\n\x1a\n")
	ihdr := []byte("IHDR")
	ihdr = binary.BigEndian.AppendUint32(ihdr, 9000)
	ihdr = binary.BigEndian.AppendUint32(ihdr, 9000)
	ihdr = append(ihdr, 8, 0, 0, 0, 0)
	_ = binary.Write(&data, binary.BigEndian, uint32(len(ihdr)-4))
	data.Write(ihdr)
	_ = binary.Write(&data, binary.BigEndian, crc32.ChecksumIEEE(ihdr))
	return data.Bytes()
}

// A photo over the pixel cap is refused before it is decoded (#2762), and
// that is a photo with no thumbnail, not a server error.
func TestGetThumbnail_ImageOverPixelCapIsNotFound(t *testing.T) {
	for name, withVFS := range map[string]bool{"vfs": true, "storage": false} {
		t.Run(name, func(t *testing.T) {
			engine, dir, _ := newThumbnailEngine(t, withVFS)
			if err := os.WriteFile(filepath.Join(dir, "bomb.png"), oversizePNGHeader(), 0o644); err != nil {
				t.Fatal(err)
			}

			if w := get(engine, "/api/v0/thumbnails/bomb.png?size=sm"); w.Code != http.StatusNotFound {
				t.Errorf("got %d, want 404: %s", w.Code, w.Body.String())
			}
		})
	}
}

// TestGetThumbnail_DeviceFile: a thumbnail for a file on a USB drive used to
// be generated from a disk path built by hand (#2645). It is now read through
// the drive's own namespace, which need not be on disk at all, and its hashes
// are stored against the drive.
func TestGetThumbnail_DeviceFile(t *testing.T) {
	const serial = "USB-1"
	t.Setenv("HOME", t.TempDir())
	ctx := context.Background()
	reg := vfs.NewRegistry()
	usb := vfs.NewMemVFS(vfs.FilesNamespace(serial))
	if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, vfs.NewMemVFS(vfs.FilesNamespace(""))); err != nil {
		t.Fatal(err)
	}
	if err := reg.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, usb); err != nil {
		t.Fatal(err)
	}
	data := pngBytes(t)
	for p, content := range map[string][]byte{"trip/red.png": data, "trip/raw.cr2": []byte("raw")} {
		if err := usb.Write(ctx, p, bytes.NewReader(content), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	database := dbtest.NewDB(t)
	deps := deputil.NewDependencies().WithDatabase(database).WithVFSRegistry(reg)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_thumbnails.NewRouter())

	expectSmallPNG(t, get(engine, "/api/v0/thumbnails/trip/red.png?size=sm&serial="+serial))
	rows, err := database.Queries.ListNearDuplicates(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || rows[0].DeviceSerial != serial || rows[0].RelPath != "trip/red.png" {
		t.Errorf("rows = %+v, want trip/red.png on %s", rows, serial)
	}

	for _, p := range []string{
		"/api/v0/thumbnails/trip/red.png?size=sm",                  // not on the internal drive
		"/api/v0/thumbnails/trip/red.png?size=sm&serial=UNPLUGGED", // no such drive
		"/api/v0/thumbnails/trip/raw.cr2?size=sm&serial=" + serial, // no host path to convert from
	} {
		if w := get(engine, p); w.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, want 404: %s", p, w.Code, w.Body.String())
		}
	}
}

// TestGetThumbnail_VideoKeyframe: the device renders an AV1 or VP8 video's
// thumbnail itself, with no ffmpeg to run, and still asks a client to render
// a codec it has no decoder for (#2865).
func TestGetThumbnail_VideoKeyframe(t *testing.T) {
	// Nothing on PATH, so no external process can have rendered it.
	t.Setenv("PATH", t.TempDir())
	engine, dir, _ := newThumbnailEngine(t, false)
	for _, name := range []string{"av1-opus.webm", "vp8-vorbis.webm", "h264-gop12.mp4", "hevc-aac-copy.mkv"} {
		clip, err := os.ReadFile(filepath.Join("..", "..", "..", "..", "..", "pkg", "util", "videoutil", "testdata", name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, name), clip, 0o600); err != nil {
			t.Fatal(err)
		}
	}

	for _, name := range []string{"av1-opus.webm", "vp8-vorbis.webm"} {
		expectJPEG(t, get(engine, "/api/v0/thumbnails/"+name+"?size=sm"), 96, 96)
	}
	for _, name := range []string{"h264-gop12.mp4", "hevc-aac-copy.mkv"} {
		if !clientRender(t, get(engine, "/api/v0/thumbnails/"+name+"?size=sm")) {
			t.Errorf("%s: want clientRender on the 404", name)
		}
	}
}
