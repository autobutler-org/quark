package v0_music_test

import (
	"net/http"
	"net/http/httptest"
	"reflect"
	"strings"
	"testing"

	v0_music "github.com/autobutler-org/quark/internal/server/api/v0/music"
)

// postPlay posts one play and returns the status.
func (h musicHarness) postPlay(t *testing.T, body string) int {
	t.Helper()
	w := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/api/v0/music/plays", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	h.engine.ServeHTTP(w, req)
	return w.Code
}

func TestRecordPlay(t *testing.T) {
	h := newMusicHarness(t)
	cases := []struct {
		name   string
		member bool
		body   string
		want   int
	}{
		{name: "library track", body: `{"serial":"","relPath":"shared/solo/1.flac"}`, want: http.StatusNoContent},
		{name: "member's readable track", member: true, body: `{"relPath":"shared/mixed/1.flac"}`, want: http.StatusNoContent},
		{name: "member's unreadable track", member: true, body: `{"relPath":"private/secret/1.flac"}`, want: http.StatusNotFound},
		{name: "not in the library", body: `{"relPath":"shared/nothing.mp3"}`, want: http.StatusNotFound},
		{name: "no path", body: `{"serial":""}`, want: http.StatusBadRequest},
		{name: "not json", body: `play`, want: http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h.as(h.admin)
			if tc.member {
				h.as(h.member)
			}
			if code := h.postPlay(t, tc.body); code != tc.want {
				t.Errorf("status = %d, want %d", code, tc.want)
			}
		})
	}
}

func TestListHistory(t *testing.T) {
	h := newMusicHarness(t)
	h.as(h.admin)
	for _, p := range []string{"shared/solo/1.flac", "shared/solo/1.flac", "private/secret/1.flac"} {
		if code := h.postPlay(t, `{"relPath":"`+p+`"}`); code != http.StatusNoContent {
			t.Fatalf("play %s: status %d", p, code)
		}
	}
	h.as(h.member)
	if code := h.postPlay(t, `{"relPath":"shared/mixed/2.flac"}`); code != http.StatusNoContent {
		t.Fatalf("member play: status %d", code)
	}
	cases := []struct {
		name   string
		member bool
		query  string
		want   []string
		counts []int
	}{
		{name: "most played", query: "?sort=most", want: []string{"Gamma", "Epsilon"}, counts: []int{2, 1}},
		{name: "limit", query: "?sort=most&limit=1", want: []string{"Gamma"}, counts: []int{2}},
		{name: "member sees only their own", member: true, query: "?sort=recent", want: []string{"Beta"}, counts: []int{1}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h.as(h.admin)
			if tc.member {
				h.as(h.member)
			}
			var got v0_music.HistoryResponse
			if code := h.get(t, "/api/v0/music/history"+tc.query, &got); code != http.StatusOK {
				t.Fatalf("status = %d, want 200", code)
			}
			titles, counts := []string{}, []int{}
			for _, p := range got.Tracks {
				titles = append(titles, p.Track.Title)
				counts = append(counts, p.PlayCount)
				if p.LastPlayedAt.IsZero() {
					t.Errorf("%s has no lastPlayedAt", p.Track.Title)
				}
			}
			if !reflect.DeepEqual(titles, tc.want) || !reflect.DeepEqual(counts, tc.counts) {
				t.Errorf("got %v %v, want %v %v", titles, counts, tc.want, tc.counts)
			}
		})
	}
	for _, query := range []string{"?sort=loudest", "?limit=-1"} {
		if code := h.get(t, "/api/v0/music/history"+query, nil); code != http.StatusBadRequest {
			t.Errorf("%s: status = %d, want 400", query, code)
		}
	}
}
