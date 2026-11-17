package photoutil_test

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/binary"
	"math"
	"slices"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

// gpsJPEG is photoJPEG with an EXIF segment holding only a GPS IFD, at lat
// and lon in whole degrees, minutes and hundredths of a second.
func gpsJPEG(t *testing.T, seed int, lat, lon float64) []byte {
	t.Helper()
	// TIFF header; IFD0 holding only the GPS IFD pointer; the GPS IFD with
	// the two refs inline and the two triples of rationals after it.
	const ifd0, gpsIFD = 8, 8 + 18
	const latOffset = gpsIFD + 2 + 4*12 + 4
	const lonOffset = latOffset + 24
	ref := func(v float64, pos, neg byte) uint32 {
		if v < 0 {
			return uint32(neg)
		}
		return uint32(pos)
	}
	dms := func(v float64) []uint32 {
		v = math.Abs(v)
		d := math.Floor(v)
		m := math.Floor((v - d) * 60)
		s := math.Round(((v-d)*60 - m) * 60 * 100)
		return []uint32{uint32(d), 1, uint32(m), 1, uint32(s), 100}
	}
	tiff := new(bytes.Buffer)
	le := binary.LittleEndian
	for _, v := range []any{
		[]byte("II"), uint16(42), uint32(ifd0),
		uint16(1), uint16(0x8825), uint16(4), uint32(1), uint32(gpsIFD), uint32(0),
		uint16(4),
		uint16(1), uint16(2), uint32(2), ref(lat, 'N', 'S'),
		uint16(2), uint16(5), uint32(3), uint32(latOffset),
		uint16(3), uint16(2), uint32(2), ref(lon, 'E', 'W'),
		uint16(4), uint16(5), uint32(3), uint32(lonOffset),
		uint32(0),
		dms(lat), dms(lon),
	} {
		_ = binary.Write(tiff, le, v)
	}
	payload := append([]byte("Exif\x00\x00"), tiff.Bytes()...)
	segment := []byte{0xFF, 0xE1, 0, 0}
	binary.BigEndian.PutUint16(segment[2:], uint16(len(payload)+2))
	segment = append(segment, payload...)
	plain := photoJPEG(t, seed)
	return append(append(append([]byte{}, plain[:2]...), segment...), plain[2:]...)
}

// TestStorePhotoHashes_RecordsLocation: storing a photo from its file records
// the GPS position in its EXIF (#3557), and a photo with none, or a 0,0 one,
// is stored as read with no position.
func TestStorePhotoHashes_RecordsLocation(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	for relPath, source := range map[string][]byte{
		"edinburgh.jpg":   gpsJPEG(t, 1, 55.9533, -3.1883),
		"sydney.jpg":      gpsJPEG(t, 2, -33.8568, 151.2153),
		"null-island.jpg": gpsJPEG(t, 3, 0, 0),
		"plain.jpg":       photoJPEG(t, 4),
	} {
		if _, err := photoutil.StorePhotoHashes(photoutil.StorePhotoHashesParams{
			Ctx: ctx, Queries: database.Queries, Serial: "", RelPath: relPath, Source: bytes.NewReader(source),
		}); err != nil {
			t.Fatal(err)
		}
	}
	rows, err := database.Queries.ListPhotoLocations(ctx)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string][2]float64{}
	for _, r := range rows {
		got[r.RelPath] = [2]float64{r.Latitude.Float64, r.Longitude.Float64}
	}
	near := func(a, b float64) bool { return math.Abs(a-b) < 1e-4 }
	if len(got) != 2 {
		t.Fatalf("stored positions = %v, want edinburgh and sydney only", got)
	}
	if p := got["edinburgh.jpg"]; !near(p[0], 55.9533) || !near(p[1], -3.1883) {
		t.Errorf("edinburgh = %v", p)
	}
	if p := got["sydney.jpg"]; !near(p[0], -33.8568) || !near(p[1], 151.2153) {
		t.Errorf("sydney = %v", p)
	}
}

// TestValidPosition keeps a map off a photo with no fix, a 0,0 fix, or one
// outside the globe.
func TestValidPosition(t *testing.T) {
	for _, tc := range []struct {
		name string
		data *photoutil.ExifData
		ok   bool
	}{
		{"nil", nil, false},
		{"no gps", &photoutil.ExifData{Latitude: 10, Longitude: 10}, false},
		{"zero zero", &photoutil.ExifData{HasGPS: true}, false},
		{"lat out of range", &photoutil.ExifData{HasGPS: true, Latitude: 91, Longitude: 3}, false},
		{"lon out of range", &photoutil.ExifData{HasGPS: true, Latitude: 1, Longitude: -181}, false},
		{"nan", &photoutil.ExifData{HasGPS: true, Latitude: math.NaN(), Longitude: 3}, false},
		{"inf", &photoutil.ExifData{HasGPS: true, Latitude: 3, Longitude: math.Inf(1)}, false},
		{"pole", &photoutil.ExifData{HasGPS: true, Latitude: 90, Longitude: 0}, true},
		{"antimeridian", &photoutil.ExifData{HasGPS: true, Latitude: -17, Longitude: 180}, true},
		{"edinburgh", &photoutil.ExifData{HasGPS: true, Latitude: 55.9533, Longitude: -3.1883}, true},
	} {
		if _, _, ok := photoutil.ValidPosition(tc.data); ok != tc.ok {
			t.Errorf("%s: ok = %v, want %v", tc.name, ok, tc.ok)
		}
	}
}

// seedLocation stores a read row for relPath at lat,lon, or a read row with
// no position when valid is false.
func seedLocation(t *testing.T, q db.Querier, relPath string, lat, lon float64, valid bool, taken time.Time) {
	t.Helper()
	if err := q.UpsertPhotoHash(context.Background(), db.UpsertPhotoHashParams{
		RelPath:      relPath,
		TakenAt:      sql.NullTime{Time: taken, Valid: !taken.IsZero()},
		Latitude:     sql.NullFloat64{Float64: lat, Valid: valid},
		Longitude:    sql.NullFloat64{Float64: lon, Valid: valid},
		TakenChecked: true,
	}); err != nil {
		t.Fatal(err)
	}
}

// TestLocations_CountsAndOrder places the photos with a position, newest
// first, and counts the rest as having none, the unread among them pending.
// A stored 0,0 or out-of-range row is never placed.
func TestLocations_CountsAndOrder(t *testing.T) {
	database := dbtest.NewDB(t)
	registry := newPhotoRegistry(t, "a.jpg", "b.jpg", "c.jpg", "none.jpg", "zero.jpg", "bad.jpg", "unread.jpg")
	q := database.Queries
	seedLocation(t, q, "a.jpg", 55.95, -3.19, true, time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC))
	seedLocation(t, q, "b.jpg", 55.96, -3.18, true, time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC))
	seedLocation(t, q, "c.jpg", 55.97, -3.17, true, time.Date(2024, 6, 1, 0, 0, 0, 0, time.UTC))
	seedLocation(t, q, "none.jpg", 0, 0, false, time.Time{})
	seedLocation(t, q, "zero.jpg", 0, 0, true, time.Time{})
	seedLocation(t, q, "bad.jpg", 123, 456, true, time.Time{})

	got, err := photoutil.Locations(photoutil.LocationsParams{List: photoutil.ListPhotosParams{
		Ctx: context.Background(), Registry: registry, Access: systemAccess(t), Queries: q,
	}})
	if err != nil {
		t.Fatal(err)
	}
	paths := make([]string, 0, len(got.Points))
	for _, p := range got.Points {
		paths = append(paths, p.RelPath)
	}
	// b is newest; a and c tie on date and go by path.
	if want := []string{"b.jpg", "a.jpg", "c.jpg"}; !slices.Equal(paths, want) {
		t.Errorf("points = %v, want %v", paths, want)
	}
	if got.Total != 7 || got.Located != 3 || got.Unlocated != 4 || got.Pending != 1 {
		t.Errorf("counts = total %d located %d unlocated %d pending %d, want 7/3/4/1",
			got.Total, got.Located, got.Unlocated, got.Pending)
	}
}

// TestLocations_Filtered: a photo another account keeps private is neither
// placed nor counted for an account that cannot read it, while an admin
// sees every one.
func TestLocations_Filtered(t *testing.T) {
	database := dbtest.NewDB(t)
	registry := newPhotoRegistry(t, "shared/a.jpg", "private/b.jpg", "private/c.jpg")
	q := database.Queries
	for _, p := range []string{"shared/a.jpg", "private/b.jpg", "private/c.jpg"} {
		seedLocation(t, q, p, 48.85, 2.35, true, time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC))
	}
	locate := func(access accessutil.Access) photoutil.LocationsResult {
		t.Helper()
		got, err := photoutil.Locations(photoutil.LocationsParams{List: photoutil.ListPhotosParams{
			Ctx: context.Background(), Registry: registry, Access: access, Queries: q,
		}})
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	if got := locate(systemAccess(t)); got.Located != 3 || got.Total != 3 {
		t.Errorf("admin: located %d of %d, want 3 of 3", got.Located, got.Total)
	}
	got := locate(userAccess(t, database, "shared"))
	if got.Located != 1 || got.Total != 1 || got.Unlocated != 0 || got.Points[0].RelPath != "shared/a.jpg" {
		t.Errorf("member: %+v, want only shared/a.jpg", got)
	}
}
