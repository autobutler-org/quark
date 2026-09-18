package v0_files_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/searchutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// searchHarness is the files router with three readable files in shared/ and
// five newer unreadable ones in private/, every one indexed for content search
// (#1907).
func searchHarness(t *testing.T) accessHarness {
	t.Helper()
	h := newAccessHarness(t, false)
	old := time.Now().Add(-time.Hour)
	for _, rel := range []string{"shared/s1.txt", "shared/s2.txt", "shared/s3.txt", "private/p1.txt", "private/p2.txt", "private/p3.txt", "private/p4.txt", "private/p5.txt"} {
		writeFixture(t, h.filesDir, rel)
		if strings.HasPrefix(rel, "shared/") {
			if err := os.Chtimes(filepath.Join(h.filesDir, filepath.FromSlash(rel)), old, old); err != nil {
				t.Fatal(err)
			}
		}
		if err := searchutil.UpsertContent(context.Background(), h.database.Db, "", rel, "needle in "+rel); err != nil {
			t.Fatal(err)
		}
	}
	h.grant(t, "shared", accessutil.Read)
	return h
}

// paths decodes a listing of files or content matches and returns the path of
// each, in response order.
func (h accessHarness) paths(t *testing.T, path string) []string {
	t.Helper()
	w := h.get(path)
	if w.Code != http.StatusOK {
		t.Fatalf("GET %s = %d: %s", path, w.Code, w.Body.String())
	}
	var entries []struct {
		DirPath string `json:"dirPath"`
		RelPath string `json:"relPath"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &entries); err != nil {
		t.Fatalf("decode %s: %v", w.Body.String(), err)
	}
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, filepath.ToSlash(e.DirPath+e.RelPath))
	}
	return out
}

func allShared(paths []string) bool {
	for _, p := range paths {
		if !strings.HasPrefix(p, "shared/") {
			return false
		}
	}
	return true
}

func TestSearchAccess_NonAdminSeesOnlyReadableAndFullPages(t *testing.T) {
	h := searchHarness(t)
	byType := "/api/v0/files/by-type?fileType=" + url.QueryEscape(string(storageutil.DetermineFileTypeFromPath("x.txt")))

	for path, want := range map[string]int{
		"/api/v0/files/search?query=.txt": 3,
		"/api/v0/files/recent?limit=2":    2,
		byType:                            3,
		"/api/v0/files/search/content?q=needle&limit=2":  2,
		"/api/v0/files/search/content?q=needle&limit=50": 3,
	} {
		if got := h.paths(t, path); len(got) != want || !allShared(got) {
			t.Errorf("GET %s = %v, want %d files, all in shared/", path, got, want)
		}
	}
}

func TestSearchAccess_AdminUnchanged(t *testing.T) {
	h := searchHarness(t)
	*h.principal = accessutil.System
	byType := "/api/v0/files/by-type?fileType=" + url.QueryEscape(string(storageutil.DetermineFileTypeFromPath("x.txt")))

	for path, want := range map[string]int{
		"/api/v0/files/search?query=.txt": 8,
		byType:                            8,
		"/api/v0/files/search/content?q=needle&limit=50": 8,
	} {
		if got := h.paths(t, path); len(got) != want {
			t.Errorf("admin GET %s = %v, want %d", path, got, want)
		}
	}
	if got := h.paths(t, "/api/v0/files/recent?limit=2"); len(got) != 2 || allShared(got) {
		t.Errorf("admin recent = %v, want the two newest, from private/", got)
	}
}
