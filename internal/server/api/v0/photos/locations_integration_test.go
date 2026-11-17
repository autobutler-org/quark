package v0_photos_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

// locations lists GET /photos/locations as whoever the harness acts as.
func (h photoHarness) locations(t *testing.T) photoutil.LocationsResult {
	t.Helper()
	w := h.do(http.MethodGet, "/api/v0/photos/locations", "")
	var got photoutil.LocationsResult
	if w.Code != http.StatusOK {
		t.Fatalf("locations = %d %s", w.Code, w.Body.String())
	}
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatal(err)
	}
	return got
}

// TestListLocations_AccessChecked: a photo the account cannot read never
// shows up as a point, in the counts, or as a cover; an admin sees every
// placed photo (#3557).
func TestListLocations_AccessChecked(t *testing.T) {
	h := newPhotoHarness(t)
	for _, rel := range []string{"shared/a.jpg", "private/c.jpg"} {
		if err := h.database.Queries.UpsertPhotoHash(context.Background(), db.UpsertPhotoHashParams{
			RelPath:      rel,
			Latitude:     sql.NullFloat64{Float64: 55.9533, Valid: true},
			Longitude:    sql.NullFloat64{Float64: -3.1883, Valid: true},
			TakenChecked: true,
		}); err != nil {
			t.Fatal(err)
		}
	}

	admin := h.locations(t)
	if admin.Total != 3 || admin.Located != 2 || admin.Unlocated != 1 || admin.Pending != 1 {
		t.Errorf("admin = %+v, want 3 total, 2 located, 1 pending", admin)
	}

	*h.principal = accessutil.Principal{UserID: h.userID}
	h.grant(t, "shared", accessutil.Read)
	member := h.locations(t)
	if member.Total != 2 || member.Located != 1 || len(member.Points) != 1 || member.Points[0].RelPath != "shared/a.jpg" {
		t.Errorf("member = %+v, want only shared/a.jpg placed of 2", member)
	}
	for _, p := range member.Points {
		if p.RelPath == "private/c.jpg" {
			t.Errorf("member sees private/c.jpg on the map")
		}
	}
}

// TestGetMapTile serves a tile of the offline pack, and 404s a tile the pack
// lacks or a path that names no tile.
func TestGetMapTile(t *testing.T) {
	h := newPhotoHarness(t)
	dir := filepath.Join(photoutil.MapTilesDir(), "3", "4", "2.png")
	if err := os.MkdirAll(filepath.Dir(dir), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(dir, []byte("\x89PNG tile"), 0o644); err != nil {
		t.Fatal(err)
	}
	w := h.do(http.MethodGet, "/api/v0/photos/map-tiles/3/4/2", "")
	if w.Code != http.StatusOK || w.Body.String() != "\x89PNG tile" || w.Header().Get("Content-Type") != "image/png" {
		t.Errorf("tile = %d %q %q", w.Code, w.Header().Get("Content-Type"), w.Body.String())
	}
	for _, path := range []string{"3/4/3", "3/8/0", "-1/0/0", "3/..%2F..%2F/2", "20/0/0"} {
		if w := h.do(http.MethodGet, "/api/v0/photos/map-tiles/"+path, ""); w.Code != http.StatusNotFound {
			t.Errorf("%s = %d, want 404", path, w.Code)
		}
	}
}
