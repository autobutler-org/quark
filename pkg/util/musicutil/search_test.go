package musicutil_test

import (
	"context"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/musicutil"
)

// TestSearch_MatchesTagsWithinAccess finds tracks by any tag, honors a column
// filter, folds accents, and never returns a track the caller cannot read.
func TestSearch_MatchesTagsWithinAccess(t *testing.T) {
	database := library(t)
	seed(t, database.Db, track{path: "shared/cafe/1.flac", title: "Café Song", artist: "Dee", album: "Cafés", genre: "Pop"})
	ctx := context.Background()
	admin, shared := adminAccess(t), memberAccess(t, database, "shared")
	search := func(query string, member bool) []string {
		t.Helper()
		access := admin
		if member {
			access = shared
		}
		got, err := musicutil.Search(musicutil.SearchParams{Ctx: ctx, DB: database.Db, Access: access, Query: query})
		if err != nil {
			t.Fatalf("Search(%q): %v", query, err)
		}
		out := []string{}
		for _, r := range got.Results {
			out = append(out, r.Track.Title)
			if !strings.Contains(r.Snippet, "<b>") {
				t.Errorf("snippet %q has no highlighted match", r.Snippet)
			}
		}
		return out
	}

	if got := search("ann", false); len(got) != 3 {
		t.Errorf("admin search ann = %v, want the three Ann tracks", got)
	}
	if got := search("ann", true); len(got) != 2 {
		t.Errorf("member search ann = %v, want only the two shared Ann tracks", got)
	}
	if got := search("secret", true); len(got) != 0 {
		t.Errorf("member search secret = %v, want nothing from the private folder", got)
	}
	if got := search("genre:jazz", false); len(got) != 1 || got[0] != "Gamma" {
		t.Errorf("search genre:jazz = %v, want [Gamma]", got)
	}
	if got := search("cafe", true); len(got) != 1 || got[0] != "Café Song" {
		t.Errorf("search cafe = %v, want the accented track", got)
	}
	if got := search(`odd "quote`, false); len(got) != 0 {
		t.Errorf("search with a stray quote = %v, want no matches and no error", got)
	}
}
