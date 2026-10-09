package photoutil_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// exifJPEG is photoJPEG with an EXIF segment whose DateTimeOriginal is taken,
// written "2006:01:02 15:04:05" the way cameras write it.
func exifJPEG(t *testing.T, seed int, taken string) []byte {
	t.Helper()
	// TIFF header; IFD0 holding only the pointer to the Exif IFD; the Exif IFD
	// holding only DateTimeOriginal (ASCII); then the string.
	const ifd0, exifIFD, dateOffset = 8, 8 + 18, 8 + 18 + 18
	value := append([]byte(taken), 0)
	tiff := new(bytes.Buffer)
	le := binary.LittleEndian
	for _, v := range []any{
		[]byte("II"), uint16(42), uint32(ifd0),
		uint16(1), uint16(0x8769), uint16(4), uint32(1), uint32(exifIFD), uint32(0),
		uint16(1), uint16(0x9003), uint16(2), uint32(len(value)), uint32(dateOffset), uint32(0),
		value,
	} {
		_ = binary.Write(tiff, le, v)
	}

	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)
	segment := []byte{0xFF, 0xE1, 0, 0}
	binary.BigEndian.PutUint16(segment[2:], uint16(len(payload)+2))
	segment = append(segment, payload...)

	plain := photoJPEG(t, seed)
	// After the SOI marker, before everything else.
	return append(append(append([]byte{}, plain[:2]...), segment...), plain[2:]...)
}

// takenAtRows lists the stored capture dates, keyed by path.
func takenAtRows(t *testing.T, q *db.Queries) map[string]time.Time {
	t.Helper()
	rows, err := q.ListPhotoTakenAt(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]time.Time{}
	for _, r := range rows {
		out[r.RelPath] = r.TakenAt.Time
	}
	return out
}

// localTime parses an EXIF-style time in the Quark's own zone, which is how a
// date with no offset is read.
func localTime(t *testing.T, s string) time.Time {
	t.Helper()
	v, err := time.ParseInLocation("2006:01:02 15:04:05", s, time.Local)
	if err != nil {
		t.Fatal(err)
	}
	return v
}

// TestStorePhotoHashes_RecordsTakenAt: storing a photo's hashes from its file
// records its capture date (#2592), a write without the file keeps the date,
// and a photo with no EXIF date is stored as read, with none.
func TestStorePhotoHashes_RecordsTakenAt(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	store := func(relPath string, source []byte) {
		t.Helper()
		params := photoutil.StorePhotoHashesParams{
			Ctx: ctx, Queries: database.Queries, Serial: "dev", RelPath: relPath, DHash: "0000000000000001",
		}
		if source != nil {
			params.Source = bytes.NewReader(source)
		}
		if _, err := photoutil.StorePhotoHashes(params); err != nil {
			t.Fatal(err)
		}
	}

	store("trip.jpg", exifJPEG(t, 1, "2019:07:04 12:30:00"))
	store("plain.jpg", photoJPEG(t, 2))
	want := localTime(t, "2019:07:04 12:30:00")
	if got := takenAtRows(t, database.Queries); len(got) != 1 || !got["trip.jpg"].Equal(want) {
		t.Fatalf("capture dates = %v, want only trip.jpg at %v", got, want)
	}

	// A client thumbnail with no source file keeps what was read before.
	store("trip.jpg", nil)
	if got := takenAtRows(t, database.Queries)["trip.jpg"]; !got.Equal(want) {
		t.Errorf("after a write without the file, trip.jpg = %v, want %v", got, want)
	}

	states, err := database.Queries.ListPhotoHashStates(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range states {
		if !s.TakenChecked {
			t.Errorf("%s: taken_checked = false, want true", s.RelPath)
		}
	}
}

// TestBackfillHashes_DatesHashedPhotosWithoutRehashing: every row a device
// stored before #2592 is complete but undated. The backfill reads its EXIF
// alone, leaves its hashes as they were, and reads nothing on a second run.
func TestBackfillHashes_DatesHashedPhotosWithoutRehashing(t *testing.T) {
	const serial = "USB-PHOTOS"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "old.jpg"), exifJPEG(t, 1, "2018:02:03 04:05:06"), 0o644); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	seedHashes(t, database.Queries, []hashRow{{serial, "old.jpg", "00000000000000aa", "kept"}})

	params := photoutil.BackfillHashesParams{
		Ctx: context.Background(), Queries: database.Queries,
		Storage: storageutil.NewStorageService(usbDetector{mountPoint: mountPoint, serial: serial}),
	}
	res, err := photoutil.BackfillHashes(params)
	if err != nil {
		t.Fatal(err)
	}
	if res != (photoutil.BackfillHashesResult{Scanned: 1, Dated: 1}) {
		t.Fatalf("result = %+v, want 1 scanned and 1 dated", res)
	}
	if got := hashRows(t, database.Queries)["old.jpg"]; got.Dhash.String != "00000000000000aa" || got.ContentHash.String != "kept" {
		t.Errorf("old.jpg was rehashed: %+v", got)
	}
	if got, want := takenAtRows(t, database.Queries)["old.jpg"], localTime(t, "2018:02:03 04:05:06"); !got.Equal(want) {
		t.Errorf("old.jpg taken at %v, want %v", got, want)
	}

	again, err := photoutil.BackfillHashes(params)
	if err != nil {
		t.Fatal(err)
	}
	if again != (photoutil.BackfillHashesResult{Scanned: 1}) {
		t.Errorf("second run = %+v, want nothing read", again)
	}
}

// TestListPhotos_SortByTaken: the taken sort orders by capture date, standing
// in the modified time for a photo with none, and reports the dates it used.
func TestListPhotos_SortByTaken(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	registry := newPhotoRegistry(t, "2019.jpg", "undated.jpg", "2023.jpg")
	for relPath, taken := range map[string]time.Time{
		"2019.jpg": time.Date(2019, 7, 4, 12, 0, 0, 0, time.UTC),
		"2023.jpg": time.Date(2023, 1, 1, 12, 0, 0, 0, time.UTC),
	} {
		if err := database.Queries.UpsertPhotoHash(ctx, db.UpsertPhotoHashParams{
			RelPath: relPath, TakenAt: sql.NullTime{Time: taken, Valid: true}, TakenChecked: true,
		}); err != nil {
			t.Fatal(err)
		}
	}

	list := func(sortBy, order string) []photoutil.PhotoSummary {
		t.Helper()
		page, err := photoutil.ListPhotos(photoutil.ListPhotosParams{
			Ctx: ctx, Registry: registry, Access: systemAccess(t), Queries: database.Queries,
			Sort: sortBy, Order: order, Limit: 50,
		})
		if err != nil {
			t.Fatal(err)
		}
		return page.Photos
	}

	// undated.jpg was written just now, so its stand-in date is the newest.
	newest := list(photoutil.SortTaken, photoutil.OrderDesc)
	if got, want := summaryNames(newest), []string{"undated.jpg", "2023.jpg", "2019.jpg"}; !equalStrings(got, want) {
		t.Errorf("taken desc = %v, want %v", got, want)
	}
	if got := summaryNames(list(photoutil.SortTaken, photoutil.OrderAsc)); !equalStrings(got, []string{"2019.jpg", "2023.jpg", "undated.jpg"}) {
		t.Errorf("taken asc = %v", got)
	}
	taken := map[string]int64{}
	for _, p := range newest {
		taken[p.FileName] = p.TakenAt
	}
	if taken["2019.jpg"] != time.Date(2019, 7, 4, 12, 0, 0, 0, time.UTC).Unix() || taken["undated.jpg"] != 0 {
		t.Errorf("takenAt = %v, want 2019.jpg's date and none for undated.jpg", taken)
	}

	// The added sort neither reads nor reports capture dates.
	for _, p := range list(photoutil.SortAdded, photoutil.OrderDesc) {
		if p.TakenAt != 0 {
			t.Errorf("added sort reported takenAt for %s", p.FileName)
		}
	}
}

func summaryNames(photos []photoutil.PhotoSummary) []string {
	names := make([]string, len(photos))
	for i, p := range photos {
		names[i] = p.FileName
	}
	return names
}

func equalStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
