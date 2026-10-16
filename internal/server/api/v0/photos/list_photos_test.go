package v0_photos_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/binary"
	"encoding/json"
	"image"
	"image/jpeg"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/gin-gonic/gin"
)

// TestListPhotos_SortByNameAscending verifies GET /photos?sort=name&order=asc
// returns photos ordered by filename rather than the default newest-first.
func TestListPhotos_SortByNameAscending(t *testing.T) {
	engine, mem := newPhotosEngineWithNS(t)
	ctx := context.Background()
	for _, name := range []string{"charlie.jpg", "alpha.jpg", "bravo.jpg"} {
		if err := mem.Write(ctx, "/"+name, strings.NewReader("img"), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
			t.Fatalf("seed %s: %v", name, err)
		}
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos?sort=name&order=asc", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}

	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Photos) != 3 {
		t.Fatalf("got %d photos, want 3", len(resp.Photos))
	}
	want := []string{"alpha.jpg", "bravo.jpg", "charlie.jpg"}
	for i, name := range want {
		if resp.Photos[i].FileName != name {
			t.Fatalf("photo[%d] = %q, want %q", i, resp.Photos[i].FileName, name)
		}
	}
}

// TestListPhotos_DefaultSortUnchanged verifies omitting sort/order still
// returns the historical newest-first order.
func TestListPhotos_DefaultSortUnchanged(t *testing.T) {
	engine, mem := newPhotosEngineWithNS(t)
	ctx := context.Background()
	if err := mem.Write(ctx, "/a.jpg", strings.NewReader("img"), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
		t.Fatalf("seed: %v", err)
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Photos) != 1 || resp.Photos[0].FileName != "a.jpg" {
		t.Fatalf("unexpected response: %+v", resp)
	}
}

// TestListPhotos_SortByTaken verifies GET /photos?sort=taken orders by the
// stored capture date and reports it as takenAt (#2592).
func TestListPhotos_SortByTaken(t *testing.T) {
	reg := vfs.NewRegistry()
	mem := vfs.NewMemVFS("files")
	if err := reg.Register(vfs.Namespace{ID: "files", Description: "files"}, mem); err != nil {
		t.Fatalf("Register: %v", err)
	}
	database := dbtest.NewDB(t)
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(database)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_photos.NewRouter())

	ctx := context.Background()
	taken := map[string]time.Time{
		"old.jpg": time.Date(2019, 7, 4, 12, 0, 0, 0, time.UTC),
		"new.jpg": time.Date(2023, 1, 1, 12, 0, 0, 0, time.UTC),
	}
	for name, at := range taken {
		if err := mem.Write(ctx, "/"+name, strings.NewReader("img"), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
			t.Fatalf("seed %s: %v", name, err)
		}
		if err := database.Queries.UpsertPhotoHash(ctx, db.UpsertPhotoHashParams{
			RelPath: name, TakenAt: sql.NullTime{Time: at, Valid: true}, TakenChecked: true,
		}); err != nil {
			t.Fatal(err)
		}
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos?sort=taken&order=asc", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(resp.Photos) != 2 || resp.Photos[0].FileName != "old.jpg" || resp.Photos[1].FileName != "new.jpg" {
		t.Fatalf("photos = %+v, want old.jpg then new.jpg", resp.Photos)
	}
	if got, want := resp.Photos[0].TakenAt, taken["old.jpg"].Unix(); got != want {
		t.Errorf("old.jpg takenAt = %d, want %d", got, want)
	}
}

// exifJPEG encodes a small JPEG carrying an EXIF DateTimeOriginal of taken,
// written "2006:01:02 15:04:05" the way cameras write it.
func exifJPEG(t *testing.T, taken string) []byte {
	t.Helper()
	// TIFF header; IFD0 holding only the pointer to the Exif IFD; the Exif IFD
	// holding only DateTimeOriginal (ASCII); then the string.
	const ifd0, exifIFD, dateOffset = 8, 8 + 18, 8 + 18 + 18
	value := append([]byte(taken), 0)
	tiff := new(bytes.Buffer)
	for _, v := range []any{
		[]byte("II"), uint16(42), uint32(ifd0),
		uint16(1), uint16(0x8769), uint16(4), uint32(1), uint32(exifIFD), uint32(0),
		uint16(1), uint16(0x9003), uint16(2), uint32(len(value)), uint32(dateOffset), uint32(0),
		value,
	} {
		_ = binary.Write(tiff, binary.LittleEndian, v)
	}
	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)
	segment := []byte{0xFF, 0xE1, 0, 0}
	binary.BigEndian.PutUint16(segment[2:], uint16(len(payload)+2))
	segment = append(segment, payload...)

	plain := new(bytes.Buffer)
	if err := jpeg.Encode(plain, image.NewGray(image.Rect(0, 0, 8, 8)), nil); err != nil {
		t.Fatal(err)
	}
	// After the SOI marker, before everything else.
	return append(append(append([]byte{}, plain.Bytes()[:2]...), segment...), plain.Bytes()[2:]...)
}

// TestListPhotos_SortByTakenDatesFreshUpload: a photo uploaded a moment ago,
// which no thumbnail or startup backfill has read, is listed under sort=taken
// with its EXIF capture date at once, not under its upload date (#3356).
func TestListPhotos_SortByTakenDatesFreshUpload(t *testing.T) {
	reg := vfs.NewRegistry()
	mem := vfs.NewMemVFS("files")
	if err := reg.Register(vfs.Namespace{ID: "files", Description: "files"}, mem); err != nil {
		t.Fatalf("Register: %v", err)
	}
	deps := deputil.NewDependencies().WithVFSRegistry(reg).WithDatabase(dbtest.NewDB(t))
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c = ctxutil.With(c, "principal", accessutil.System)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_photos.NewRouter())

	const taken = "2022:09:22 08:15:00"
	if err := mem.Write(context.Background(), "/trip.jpg", bytes.NewReader(exifJPEG(t, taken)), vfs.WriteOptions{ContentType: "image/jpeg"}); err != nil {
		t.Fatalf("upload: %v", err)
	}

	w := doPhotosReq(engine, http.MethodGet, "/api/v0/photos?sort=taken", nil)
	if w.Code != http.StatusOK {
		t.Fatalf("list returned %d: %s", w.Code, w.Body.String())
	}
	var resp v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	want, err := time.ParseInLocation("2006:01:02 15:04:05", taken, time.Local)
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.Photos) != 1 || resp.Photos[0].TakenAt != want.Unix() {
		t.Fatalf("photos = %+v, want trip.jpg with takenAt %d", resp.Photos, want.Unix())
	}
	if resp.PendingDates != 0 {
		t.Errorf("pendingDates = %d, want 0", resp.PendingDates)
	}
}
