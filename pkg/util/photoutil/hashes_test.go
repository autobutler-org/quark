package photoutil_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// photoJPEG encodes a 64x48 JPEG whose pixels depend on seed, so two seeds
// hash apart.
func photoJPEG(t *testing.T, seed int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 64, 48))
	for y := range 48 {
		for x := range 64 {
			v := uint8((x*4 + y*seed*7) % 256)
			img.Set(x, y, color.RGBA{R: v, G: 255 - v, B: uint8(seed * 40), A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, nil); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// hashRows lists the photo_hashes rows that have a dHash, keyed by path.
func hashRows(t *testing.T, q *db.Queries) map[string]db.ListNearDuplicatesRow {
	t.Helper()
	rows, err := q.ListNearDuplicates(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]db.ListNearDuplicatesRow{}
	for _, r := range rows {
		out[r.RelPath] = r
	}
	return out
}

// TestBackfillHashes: photos whose thumbnails were cached before hashes were
// stored had no photo_hashes row, so duplicate detection never saw them
// (#1666). The backfill hashes them, leaves complete rows alone, and does
// nothing on a second run.
func TestBackfillHashes(t *testing.T) {
	const serial = "USB-PHOTOS"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	same := photoJPEG(t, 1)
	for name, data := range map[string][]byte{
		"a.jpg":        same,
		"copy/a.jpg":   same,
		"b.jpg":        photoJPEG(t, 3),
		"done.jpg":     photoJPEG(t, 5),
		"notes.txt":    []byte("not a photo"),
		"legacy/c.jpg": photoJPEG(t, 2),
	} {
		full := filepath.Join(filesDir, name)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	svc := storageutil.NewStorageService(usbDetector{mountPoint: mountPoint, serial: serial})
	database := dbtest.NewDB(t)
	ctx := context.Background()
	// A complete row is trusted as it is; a legacy row with only the dHash
	// the old thumbnail path wrote gets its content hash.
	seedHashes(t, database.Queries, []hashRow{
		{serial, "done.jpg", "00000000000000aa", "kept"},
		{serial, "legacy/c.jpg", "00000000000000bb", ""},
	})

	params := photoutil.BackfillHashesParams{
		Ctx: ctx, Queries: database.Queries, Registry: deviceRegistry(t, svc), IOSemaphore: iosemutil.NewWithConcurrency(1),
	}
	res, err := photoutil.BackfillHashes(params)
	if err != nil {
		t.Fatal(err)
	}
	// done.jpg's hashes are complete, so only its capture date is read.
	if res != (photoutil.BackfillHashesResult{Scanned: 5, Hashed: 4, Dated: 1}) {
		t.Fatalf("result = %+v, want 5 scanned, 4 hashed and 1 dated", res)
	}

	rows := hashRows(t, database.Queries)
	sum := sha256.Sum256(same)
	for _, p := range []string{"a.jpg", "copy/a.jpg"} {
		if rows[p].ContentHash.String != hex.EncodeToString(sum[:]) || !rows[p].Dhash.Valid {
			t.Errorf("%s: row = %+v, want its dHash and SHA-256", p, rows[p])
		}
	}
	if got := rows["done.jpg"]; got.Dhash.String != "00000000000000aa" || got.ContentHash.String != "kept" {
		t.Errorf("done.jpg was rehashed: %+v", got)
	}
	if got := rows["legacy/c.jpg"]; !got.ContentHash.Valid || got.Dhash.String == "00000000000000bb" {
		t.Errorf("legacy/c.jpg: row = %+v, want a fresh dHash and a content hash", got)
	}

	// The identical pair comes back as one exact group.
	groups := listGroups(t, photoutil.ListDuplicatesParams{
		Ctx: ctx, Queries: database.Queries, Threshold: 0, Access: systemAccess(t),
	})
	if want := []string{"exact: " + serial + "|a.jpg " + serial + "|copy/a.jpg"}; !reflect.DeepEqual(groups, want) {
		t.Errorf("groups = %q, want %q", groups, want)
	}

	again, err := photoutil.BackfillHashes(params)
	if err != nil {
		t.Fatal(err)
	}
	if again != (photoutil.BackfillHashesResult{Scanned: 5}) {
		t.Errorf("second run = %+v, want nothing hashed", again)
	}
}

// TestBackfillHashesKeepsADHashItCannotDecode: a photo only a client could
// render keeps the dHash it sent and gains a content hash.
func TestBackfillHashesKeepsADHashItCannotDecode(t *testing.T) {
	const serial = "USB-PHOTOS"
	mountPoint := t.TempDir()
	filesDir := filepath.Join(mountPoint, "quark", "data", "files")
	if err := os.MkdirAll(filesDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(filesDir, "x.jpg"), []byte("undecodable"), 0o644); err != nil {
		t.Fatal(err)
	}
	database := dbtest.NewDB(t)
	seedHashes(t, database.Queries, []hashRow{{serial, "x.jpg", "00000000000000cc", ""}})

	if _, err := photoutil.BackfillHashes(photoutil.BackfillHashesParams{
		Ctx: context.Background(), Queries: database.Queries,
		Registry: deviceRegistry(t, storageutil.NewStorageService(usbDetector{mountPoint: mountPoint, serial: serial})),
	}); err != nil {
		t.Fatal(err)
	}
	got := hashRows(t, database.Queries)["x.jpg"]
	sum := sha256.Sum256([]byte("undecodable"))
	if got.Dhash.String != "00000000000000cc" || got.ContentHash.String != hex.EncodeToString(sum[:]) {
		t.Errorf("row = %+v, want the old dHash and the file's SHA-256", got)
	}
}

// TestStorePhotoHashes_SkipsTrashAndCanonicalizes: the row is keyed the way
// ListDuplicates and the access checks spell the path, and a trashed photo
// gets none.
func TestStorePhotoHashes_SkipsTrashAndCanonicalizes(t *testing.T) {
	database := dbtest.NewDB(t)
	for _, p := range []string{"/trip//a.jpg", ".trash/x/a.jpg"} {
		if _, err := photoutil.StorePhotoHashes(photoutil.StorePhotoHashesParams{
			Ctx: context.Background(), Queries: database.Queries, RelPath: p,
			DHash: "0000000000000001", Source: bytes.NewReader([]byte("a")),
		}); err != nil {
			t.Fatal(err)
		}
	}
	rows := hashRows(t, database.Queries)
	if len(rows) != 1 || !rows["trip/a.jpg"].ContentHash.Valid {
		t.Errorf("rows = %+v, want only trip/a.jpg", rows)
	}
}
