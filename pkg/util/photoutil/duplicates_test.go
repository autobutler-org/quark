package photoutil_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

type hashRow struct{ serial, path, dhash, content string }

func seedHashes(t *testing.T, q *db.Queries, rows []hashRow) {
	t.Helper()
	for _, row := range rows {
		if err := q.UpsertPhotoHash(context.Background(), db.UpsertPhotoHashParams{
			DeviceSerial: row.serial,
			RelPath:      row.path,
			Dhash:        sql.NullString{String: row.dhash, Valid: row.dhash != ""},
			ContentHash:  sql.NullString{String: row.content, Valid: row.content != ""},
		}); err != nil {
			t.Fatal(err)
		}
	}
}

// listGroups flattens the groups to "kind: serial|path, ..." in the order
// they came back, which is itself under test.
func listGroups(t *testing.T, params photoutil.ListDuplicatesParams) []string {
	t.Helper()
	result, err := photoutil.ListDuplicates(params)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, g := range result.Groups {
		s := g.Kind + ":"
		for _, p := range g.Photos {
			s += " " + p.DeviceSerial + "|" + p.RelPath
		}
		out = append(out, s)
	}
	return out
}

// TestListDuplicates_EachPhotoOnce: identical files share a dHash, so they used
// to come back twice, once as an exact group and again inside a near group
// (#1666). Each photo is now in one group, exact only when every copy shares a
// content hash, and the order is stable.
func TestListDuplicates_EachPhotoOnce(t *testing.T) {
	database := dbtest.NewDB(t)
	seedHashes(t, database.Queries, []hashRow{
		// Two identical files and a near copy: one near group.
		{"", "z/a.jpg", "00000000000000ff", "h1"},
		{"", "a/a copy.jpg", "00000000000000ff", "h1"},
		{"", "m/a edited.jpg", "00000000000000fe", "h9"},
		// Two identical files alone: one exact group.
		{"USB", "b.jpg", "ffff000000000000", "h2"},
		{"", "b.jpg", "ffff000000000000", "h2"},
		// Identical files with no dHash: an exact group from the content pass.
		{"", "raw/c.cr2", "", "h3"},
		{"", "raw/c copy.cr2", "", "h3"},
		// Nothing like anything else.
		{"", "lonely.jpg", "f0f0f0f0f0f0f0f0", "h4"},
	})

	params := photoutil.ListDuplicatesParams{
		Ctx: context.Background(), Queries: database.Queries, Threshold: 4, Access: systemAccess(t),
	}
	want := []string{
		"exact: |b.jpg USB|b.jpg",
		"exact: |raw/c copy.cr2 |raw/c.cr2",
		"near: |a/a copy.jpg |m/a edited.jpg |z/a.jpg",
	}
	for i := range 3 {
		if got := listGroups(t, params); !reflect.DeepEqual(got, want) {
			t.Fatalf("run %d: groups = %q, want %q", i, got, want)
		}
	}
}

// TestListDuplicates_Order: exact groups come first, then near groups by their
// largest pairwise dHash distance, lowest first, whatever their paths say. A
// tie falls back to the first photo. The distance is pairwise, not from the
// seed: a/1 is 2 from each of the others, which are 4 apart.
func TestListDuplicates_Order(t *testing.T) {
	database := dbtest.NewDB(t)
	seedHashes(t, database.Queries, []hashRow{
		{"", "a/1.jpg", "0000000000000000", "a1"},
		{"", "a/2.jpg", "0000000000000003", "a2"},
		{"", "a/3.jpg", "000000000000000c", "a3"},
		{"", "b/1.jpg", "ff00000000000000", "b1"},
		{"", "b/2.jpg", "ff00000000000001", "b2"},
		{"", "c/1.jpg", "00ff000000000000", "c1"},
		{"", "c/2.jpg", "00ff000000000001", "c2"},
		{"", "d/1.jpg", "f0f0000000000000", "d1"},
		{"", "d/2.jpg", "f0f0000000000007", "d2"},
		{"", "z/1.jpg", "f0f0f0f0f0f0f0f0", "z"},
		{"", "z/2.jpg", "f0f0f0f0f0f0f0f0", "z"},
		{"", "raw/1.cr2", "", "r"},
		{"", "raw/2.cr2", "", "r"},
	})

	result, err := photoutil.ListDuplicates(photoutil.ListDuplicatesParams{
		Ctx: context.Background(), Queries: database.Queries, Threshold: 4, Access: systemAccess(t),
	})
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, g := range result.Groups {
		got = append(got, fmt.Sprintf("%s %d %s", g.Kind, g.MaxDistance, g.Photos[0].RelPath))
	}
	want := []string{
		"exact 0 raw/1.cr2",
		"exact 0 z/1.jpg",
		"near 1 b/1.jpg",
		"near 1 c/1.jpg",
		"near 3 d/1.jpg",
		"near 4 a/1.jpg",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("groups = %q, want %q", got, want)
	}
	raw, err := json.Marshal(result.Groups[len(result.Groups)-1])
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(raw), `"maxDistance":4`) {
		t.Errorf("group JSON = %s, want a maxDistance of 4", raw)
	}
}

// TestListDuplicates_LeavesOutWhatIsGone: a trashed photo is not offered, and a
// photo no longer on disk is left out and forgotten, so it does not come back.
func TestListDuplicates_LeavesOutWhatIsGone(t *testing.T) {
	database := dbtest.NewDB(t)
	q := database.Queries
	seedHashes(t, q, []hashRow{
		{"", "a.jpg", "0000000000000000", "h1"},
		{"", "b.jpg", "0000000000000000", "h1"},
		{"", "gone.jpg", "0000000000000000", "h1"},
		{"", ".trash/c.jpg", "0000000000000000", "h1"},
	})
	var asked []string
	params := photoutil.ListDuplicatesParams{
		Ctx: context.Background(), Queries: q, Threshold: 4, Access: systemAccess(t),
		Exists: func(serial, relPath string) bool {
			asked = append(asked, relPath)
			return relPath != "gone.jpg"
		},
	}

	if got, want := listGroups(t, params), []string{"exact: |a.jpg |b.jpg"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("groups = %q, want %q", got, want)
	}
	rows, err := q.ListNearDuplicates(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range rows {
		if r.RelPath == "gone.jpg" {
			t.Error("the missing photo's hashes are still stored")
		}
	}
	for _, p := range asked {
		if p == ".trash/c.jpg" {
			t.Error("a trashed photo was checked on disk instead of skipped")
		}
	}
}
