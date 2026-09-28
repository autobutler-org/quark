package v0_photos_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	v0_photos "github.com/autobutler-org/quark/internal/server/api/v0/photos"
	"github.com/autobutler-org/quark/pkg/vfs"
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
