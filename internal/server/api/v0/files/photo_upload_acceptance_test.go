package v0_files_test

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"io"
	"math"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// Photo upload acceptance (#3487): a photo goes in through the real upload
// route and comes back out through the photo library's own routes, so what is
// checked is the seam between them — what lands, what the library lists, and
// whether the capture date and the rest of the EXIF survive the trip.
//
// The photo import sends one multipart request per pick with keepBoth set
// (photos_controller._uploadToLibrary), so that is what these requests do.

// photoUploadHarness serves the files and photo routes over one dependency
// graph: a real files directory, a migrated database and an event bus.
type photoUploadHarness struct {
	engine   *gin.Engine
	filesDir string
	events   <-chan eventbus.Event
}

func newPhotoUploadHarness(t *testing.T) photoUploadHarness {
	t.Helper()
	// Nothing here should reach the real ~/quark/data.
	t.Setenv("HOME", t.TempDir())
	deps, filesDir := newStorageVFSDeps(t)
	deps = deps.WithDatabase(dbtest.NewDB(t))
	events, unsubscribe := deps.EventBus().Subscribe(t.Name())
	t.Cleanup(unsubscribe)
	engine := newEngineForDeps(deps)
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_photos.NewRouter())
	return photoUploadHarness{engine: engine, filesDir: filesDir, events: events}
}

// photoPart is one file of an upload request.
type photoPart struct {
	name string
	body []byte
}

// multipartBody encodes parts the way the client does, one "files" part each.
func multipartBody(t *testing.T, parts []photoPart) (*bytes.Buffer, string) {
	t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	for _, p := range parts {
		fw, err := mw.CreateFormFile("files", p.name)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := fw.Write(p.body); err != nil {
			t.Fatal(err)
		}
	}
	if err := mw.Close(); err != nil {
		t.Fatal(err)
	}
	return &buf, mw.FormDataContentType()
}

// importPhotos uploads parts in one request the way the photo import does and
// returns the response.
func (h photoUploadHarness) importPhotos(t *testing.T, parts []photoPart) (int, []string) {
	t.Helper()
	body, contentType := multipartBody(t, parts)
	return h.decodeUpload(t, doRequest(h.engine, http.MethodPost, "/api/v0/files/upload?keepBoth=true", body, contentType))
}

func (h photoUploadHarness) decodeUpload(t *testing.T, w *httptest.ResponseRecorder) (int, []string) {
	t.Helper()
	if w.Code != http.StatusOK {
		return w.Code, nil
	}
	var got struct {
		Paths []string `json:"paths"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("decode upload response: %v", err)
	}
	return w.Code, got.Paths
}

// library lists the whole photo library, sorted by capture date.
func (h photoUploadHarness) library(t *testing.T) v0_photos.PaginatedPhotosResponse {
	t.Helper()
	w := doRequest(h.engine, http.MethodGet, "/api/v0/photos?sort=taken&order=asc&limit=200", nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("list photos returned %d: %s", w.Code, w.Body.String())
	}
	var page v0_photos.PaginatedPhotosResponse
	if err := json.Unmarshal(w.Body.Bytes(), &page); err != nil {
		t.Fatalf("decode photo list: %v", err)
	}
	return page
}

func libraryNames(page v0_photos.PaginatedPhotosResponse) []string {
	names := make([]string, 0, len(page.Photos))
	for _, p := range page.Photos {
		names = append(names, p.FileName)
	}
	slices.Sort(names)
	return names
}

// metadata reads the info sheet's view of one photo.
func (h photoUploadHarness) metadata(t *testing.T, relPath string) v0_photos.PhotoMetadataJSON {
	t.Helper()
	w := doRequest(h.engine, http.MethodGet, "/api/v0/photos/metadata?relPath="+url.QueryEscape(relPath), nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("metadata of %s returned %d: %s", relPath, w.Code, w.Body.String())
	}
	var meta v0_photos.PhotoMetadataJSON
	if err := json.Unmarshal(w.Body.Bytes(), &meta); err != nil {
		t.Fatalf("decode metadata: %v", err)
	}
	return meta
}

// uploadEvents drains the events published so far and counts the uploads.
func (h photoUploadHarness) uploadEvents() int {
	n := 0
	for {
		select {
		case e := <-h.events:
			if e.Kind == eventbus.EventUpload {
				n++
			}
		default:
			return n
		}
	}
}

// assertStored fails unless the file at rel holds exactly want.
func (h photoUploadHarness) assertStored(t *testing.T, rel string, want []byte) {
	t.Helper()
	got, err := os.ReadFile(filepath.Join(h.filesDir, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatalf("read %s: %v", rel, err)
	}
	if sha256.Sum256(got) != sha256.Sum256(want) {
		t.Fatalf("%s holds %d bytes that differ from the %d uploaded", rel, len(got), len(want))
	}
}

// plainJPEG encodes a small JPEG whose pixels depend on seed, so two of them
// never share bytes.
func plainJPEG(t *testing.T, seed int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 8, 8))
	img.Set(0, 0, color.RGBA{R: uint8(seed), G: uint8(seed >> 8), B: 7, A: 255})
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 100}); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func plainPNG(t *testing.T) []byte {
	t.Helper()
	var buf bytes.Buffer
	if err := png.Encode(&buf, image.NewGray(image.Rect(0, 0, 8, 8))); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// exifTag is one TIFF directory entry; data is its value, little-endian.
type exifTag struct {
	id, typ uint16
	count   uint32
	data    []byte
}

const (
	tiffShort    = 3
	tiffASCII    = 2
	tiffLong     = 4
	tiffRational = 5
)

func asciiTag(id uint16, s string) exifTag {
	v := append([]byte(s), 0)
	return exifTag{id: id, typ: tiffASCII, count: uint32(len(v)), data: v}
}

func shortTag(id, v uint16) exifTag {
	return exifTag{id: id, typ: tiffShort, count: 1, data: binary.LittleEndian.AppendUint16(nil, v)}
}

func rationalsTag(id uint16, pairs ...uint32) exifTag {
	var data []byte
	for _, v := range pairs {
		data = binary.LittleEndian.AppendUint32(data, v)
	}
	return exifTag{id: id, typ: tiffRational, count: uint32(len(pairs) / 2), data: data}
}

// cameraExif is what a phone writes: a capture date, an orientation and a
// location.
type cameraExif struct {
	taken       string // "2006:01:02 15:04:05"
	orientation uint16
	lat, lon    [3][2]uint32 // degrees, minutes, seconds as rationals
	latRef      string
	lonRef      string
}

// exifJPEGWith encodes a JPEG carrying e in an APP1 segment: IFD0 with the
// orientation and pointers to an Exif IFD (DateTimeOriginal) and a GPS IFD.
func exifJPEGWith(t *testing.T, seed int, e cameraExif) []byte {
	t.Helper()
	ifdSize := func(n int) uint32 { return uint32(2 + 12*n + 4) }
	exifAt := 8 + ifdSize(3)
	gpsAt := exifAt + ifdSize(1)
	cursor := gpsAt + ifdSize(4)
	pointer := func(id uint16, at uint32) exifTag {
		return exifTag{id: id, typ: tiffLong, count: 1, data: binary.LittleEndian.AppendUint32(nil, at)}
	}
	r := func(v [3][2]uint32) []uint32 { return []uint32{v[0][0], v[0][1], v[1][0], v[1][1], v[2][0], v[2][1]} }
	directories := [][]exifTag{
		{shortTag(0x0112, e.orientation), pointer(0x8769, exifAt), pointer(0x8825, gpsAt)},
		{asciiTag(0x9003, e.taken)},
		{
			asciiTag(0x0001, e.latRef), rationalsTag(0x0002, r(e.lat)...),
			asciiTag(0x0003, e.lonRef), rationalsTag(0x0004, r(e.lon)...),
		},
	}

	var dirs, extra bytes.Buffer
	for _, ifd := range directories {
		_ = binary.Write(&dirs, binary.LittleEndian, uint16(len(ifd)))
		for _, tag := range ifd {
			for _, field := range []any{tag.id, tag.typ, tag.count} {
				_ = binary.Write(&dirs, binary.LittleEndian, field)
			}
			if len(tag.data) <= 4 {
				dirs.Write(append(tag.data, make([]byte, 4-len(tag.data))...))
				continue
			}
			_ = binary.Write(&dirs, binary.LittleEndian, cursor)
			extra.Write(tag.data)
			cursor += uint32(len(tag.data))
		}
		_ = binary.Write(&dirs, binary.LittleEndian, uint32(0))
	}
	tiff := append([]byte("II*\x00\x08\x00\x00\x00"), dirs.Bytes()...)
	tiff = append(tiff, extra.Bytes()...)

	payload := append([]byte("Exif\x00\x00"), tiff...)
	segment := binary.BigEndian.AppendUint16([]byte{0xFF, 0xE1}, uint16(len(payload)+2))
	segment = append(segment, payload...)
	plain := plainJPEG(t, seed)
	// After the SOI marker, before everything else.
	return append(append(append([]byte{}, plain[:2]...), segment...), plain[2:]...)
}

// seattle is 47°36'22.32"N 122°19'55.56"W.
var seattle = cameraExif{
	orientation: 6,
	lat:         [3][2]uint32{{47, 1}, {36, 1}, {2232, 100}},
	latRef:      "N",
	lon:         [3][2]uint32{{122, 1}, {19, 1}, {5556, 100}},
	lonRef:      "W",
}

// A picked batch of mixed kinds — JPEGs, a PNG, a HEIC, a RAW and its JPEG, a
// corrupt JPEG and a file that is no photo at all — lands file by file in one
// request: the response names where each one went, nothing in it aborts the
// rest, the clients are told to refresh, and the library lists every photo
// once (the text file is not a photo).
func TestPhotoUploadAcceptance_BulkMixedBatch(t *testing.T) {
	h := newPhotoUploadHarness(t)

	var parts []photoPart
	for i := range 20 {
		parts = append(parts, photoPart{fmt.Sprintf("IMG_%04d.jpg", i), plainJPEG(t, i)})
	}
	parts = append(parts,
		photoPart{"screenshot.png", plainPNG(t)},
		photoPart{"IMG_0100.heic", []byte("not decodable heic")},
		photoPart{"DSC_0001.dng", []byte("not decodable dng")},
		photoPart{"DSC_0001.jpg", plainJPEG(t, 1000)},
		photoPart{"broken.jpg", []byte("this is not a jpeg")},
		photoPart{"notes.txt", []byte("not a photo")},
	)

	code, paths := h.importPhotos(t, parts)
	if code != http.StatusOK {
		t.Fatalf("upload returned %d, want 200", code)
	}
	var want []string
	for _, p := range parts {
		want = append(want, p.name)
	}
	if !slices.Equal(paths, want) {
		t.Fatalf("per-file outcome = %v, want every file in order %v", paths, want)
	}
	for _, p := range parts {
		h.assertStored(t, p.name, p.body)
	}
	if n := h.uploadEvents(); n != 1 {
		t.Errorf("upload events = %d, want 1 so open grids refresh without a manual one", n)
	}

	page := h.library(t)
	photos := slices.DeleteFunc(slices.Clone(want), func(n string) bool { return n == "notes.txt" })
	slices.Sort(photos)
	if got := libraryNames(page); !slices.Equal(got, photos) {
		t.Fatalf("library = %v, want %v", got, photos)
	}
	if page.Total != len(photos) {
		t.Errorf("total = %d, want %d", page.Total, len(photos))
	}
	// The corrupt file and the undecodable HEIC and RAW still describe
	// themselves rather than failing the info sheet.
	for _, rel := range []string{"broken.jpg", "IMG_0100.heic", "DSC_0001.dng"} {
		if meta := h.metadata(t, rel); meta.Exif != nil {
			t.Errorf("%s reports EXIF %+v from bytes that carry none", rel, meta.Exif)
		}
	}
}

// The import keeps both copies of a name already in the library, the same
// bytes or different ones: nothing is overwritten and each copy is listed.
func TestPhotoUploadAcceptance_DuplicateNameKeepsBoth(t *testing.T) {
	h := newPhotoUploadHarness(t)
	original := plainJPEG(t, 1)
	different := plainJPEG(t, 2)

	for _, step := range []struct {
		body []byte
		want string
	}{
		{original, "IMG_0001.jpg"},
		{original, "IMG_0001_(1).jpg"},
		{different, "IMG_0001_(2).jpg"},
	} {
		code, paths := h.importPhotos(t, []photoPart{{"IMG_0001.jpg", step.body}})
		if code != http.StatusOK || !slices.Equal(paths, []string{step.want}) {
			t.Fatalf("upload = %d %v, want 200 [%s]", code, paths, step.want)
		}
	}

	h.assertStored(t, "IMG_0001.jpg", original)
	h.assertStored(t, "IMG_0001_(1).jpg", original)
	h.assertStored(t, "IMG_0001_(2).jpg", different)
	want := []string{"IMG_0001.jpg", "IMG_0001_(1).jpg", "IMG_0001_(2).jpg"}
	if got := libraryNames(h.library(t)); !slices.Equal(got, want) {
		t.Fatalf("library = %v, want %v", got, want)
	}
}

// A connection that drops inside the third file of a batch keeps the two that
// arrived, exactly once, and leaves nothing of the third under its name. The
// clients still hear about the two, and the failure names them. Sending the
// third again completes the batch without a renamed copy of anything.
func TestPhotoUploadAcceptance_InterruptedBatch(t *testing.T) {
	h := newPhotoUploadHarness(t)
	parts := []photoPart{
		{"a.jpg", plainJPEG(t, 1)},
		{"b.jpg", plainJPEG(t, 2)},
		{"c.jpg", plainJPEG(t, 3)},
	}
	body, contentType := multipartBody(t, parts)
	// Cut the body halfway through c.jpg's bytes: no closing boundary follows.
	at := bytes.Index(body.Bytes(), parts[2].body)
	if at < 0 {
		t.Fatal("c.jpg not found in the request body")
	}
	cut := io.LimitReader(body, int64(at+len(parts[2].body)/2))

	w := doRequest(h.engine, http.MethodPost, "/api/v0/files/upload?keepBoth=true", cut, contentType)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("interrupted upload returned %d, want 400: %s", w.Code, w.Body.String())
	}
	// The 400 names what landed, so the client resends c.jpg alone (#3533).
	if got := decodeUploadFailure(t, w).Landed; !slices.Equal(got, []string{"a.jpg", "b.jpg"}) {
		t.Fatalf("landed = %v, want [a.jpg b.jpg]", got)
	}
	if _, err := os.Stat(filepath.Join(h.filesDir, "c.jpg")); !os.IsNotExist(err) {
		t.Fatalf("c.jpg after the cut: stat err = %v, want not exist", err)
	}
	h.assertStored(t, "a.jpg", parts[0].body)
	h.assertStored(t, "b.jpg", parts[1].body)
	if n := h.uploadEvents(); n != 1 {
		t.Errorf("upload events = %d, want 1 for the files that landed", n)
	}
	if got := libraryNames(h.library(t)); !slices.Equal(got, []string{"a.jpg", "b.jpg"}) {
		t.Fatalf("library after the cut = %v, want [a.jpg b.jpg]", got)
	}

	if code, paths := h.importPhotos(t, parts[2:]); code != http.StatusOK || !slices.Equal(paths, []string{"c.jpg"}) {
		t.Fatalf("resending c.jpg = %d %v, want 200 [c.jpg]", code, paths)
	}
	h.assertStored(t, "c.jpg", parts[2].body)
	if got := libraryNames(h.library(t)); !slices.Equal(got, []string{"a.jpg", "b.jpg", "c.jpg"}) {
		t.Fatalf("library after resending = %v, want [a.jpg b.jpg c.jpg]", got)
	}
}

// A camera photo keeps everything it was taken with: the stored file is the
// uploaded bytes, orientation and all; the library dates it by its EXIF
// capture date in the month it was taken, not the day it was uploaded
// (#3356), even late on the last night of a month; and the info sheet reads
// its location as signed decimal degrees (#3364).
func TestPhotoUploadAcceptance_MetadataSurvives(t *testing.T) {
	h := newPhotoUploadHarness(t)
	trip := seattle
	trip.taken = "2021:03:31 23:30:00"
	photo := exifJPEGWith(t, 1, trip)

	if code, paths := h.importPhotos(t, []photoPart{{"trip.jpg", photo}}); code != http.StatusOK || !slices.Equal(paths, []string{"trip.jpg"}) {
		t.Fatalf("upload = %d %v, want 200 [trip.jpg]", code, paths)
	}
	h.assertStored(t, "trip.jpg", photo)
	f, err := os.Open(filepath.Join(h.filesDir, "trip.jpg"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	if got := photoutil.GetOrientation(f, photoutil.ImageFormatFromPath("trip.jpg")); got != 6 {
		t.Errorf("stored orientation = %d, want 6", got)
	}

	page := h.library(t)
	if len(page.Photos) != 1 {
		t.Fatalf("library = %+v, want trip.jpg alone", page.Photos)
	}
	want, err := time.ParseInLocation("2006:01:02 15:04:05", trip.taken, time.Local)
	if err != nil {
		t.Fatal(err)
	}
	got := page.Photos[0].TakenAt
	if got != want.Unix() {
		t.Fatalf("takenAt = %d, want %d", got, want.Unix())
	}
	if month := time.Unix(got, 0).In(time.Local).Month(); month != time.March {
		t.Errorf("trip.jpg groups under %s, want March", month)
	}
	if page.PendingDates != 0 {
		t.Errorf("pendingDates = %d, want 0", page.PendingDates)
	}

	meta := h.metadata(t, "trip.jpg")
	if meta.Exif == nil || meta.Exif.DateTaken == nil || meta.Exif.Latitude == nil || meta.Exif.Longitude == nil {
		t.Fatalf("info sheet EXIF = %+v, want a date and a location", meta.Exif)
	}
	if math.Abs(*meta.Exif.Latitude-47.6062) > 1e-4 || math.Abs(*meta.Exif.Longitude-(-122.3321)) > 1e-4 {
		t.Errorf("location = %v, %v, want 47.6062, -122.3321", *meta.Exif.Latitude, *meta.Exif.Longitude)
	}
}

// A RAW and the JPEG the camera wrote beside it are two photos in the
// library, each listed once, and each dated by its own EXIF where it has one.
func TestPhotoUploadAcceptance_RawJPEGPair(t *testing.T) {
	h := newPhotoUploadHarness(t)
	shot := seattle
	shot.taken = "2020:07:04 12:00:00"
	pair := []photoPart{
		{"DSC_0042.dng", []byte("not decodable dng")},
		{"DSC_0042.jpg", exifJPEGWith(t, 42, shot)},
	}

	if code, paths := h.importPhotos(t, pair); code != http.StatusOK || len(paths) != 2 {
		t.Fatalf("upload = %d %v, want 200 and both paths", code, paths)
	}
	page := h.library(t)
	if got := libraryNames(page); !slices.Equal(got, []string{"DSC_0042.dng", "DSC_0042.jpg"}) {
		t.Fatalf("library = %v, want the RAW and the JPEG", got)
	}
	want, err := time.ParseInLocation("2006:01:02 15:04:05", shot.taken, time.Local)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range page.Photos {
		if p.FileName == "DSC_0042.jpg" && p.TakenAt != want.Unix() {
			t.Errorf("DSC_0042.jpg takenAt = %d, want %d", p.TakenAt, want.Unix())
		}
	}
}
