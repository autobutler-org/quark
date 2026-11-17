package v0_videos_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"testing"
)

const (
	aviFixture        = "../../../../../pkg/util/videoutil/testdata/unsupported.avi"
	fragmentedFixture = "../../../../../pkg/util/videoutil/testdata/fragmented.mp4"
)

// videoRefusal is the body of a 422 about a video: the logs' text and the
// code a client picks its sentence from.
type videoRefusal struct {
	Error  string `json:"error"`
	Reason string `json:"reason"`
}

func refusalOf(t *testing.T, code int, body []byte) videoRefusal {
	t.Helper()
	if code != http.StatusUnprocessableEntity {
		t.Fatalf("status %d %s, want 422", code, body)
	}
	var r videoRefusal
	if err := json.Unmarshal(body, &r); err != nil {
		t.Fatalf("body %s: %v", body, err)
	}
	if r.Error == "" {
		t.Errorf("body %s has no error text", body)
	}
	return r
}

// TestAnExistingVideoThatCannotBeReadNamesWhy is #3423: a file that is there
// but is unsupported or damaged is never a 404 or a 500, and metadata,
// formats, trim and transcode all answer it with the same 422 and the same
// reason code.
func TestAnExistingVideoThatCannotBeReadNamesWhy(t *testing.T) {
	h := newHarness(t)
	copyFixture(t, aviFixture, filepath.Join(h.filesDir, "old.avi"))
	if err := os.WriteFile(filepath.Join(h.filesDir, "note.mp4"), []byte("not a video"), 0o644); err != nil {
		t.Fatal(err)
	}
	clip, err := os.ReadFile(gopFixture)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(h.filesDir, "cut.mp4"), clip[:len(clip)/2], 0o644); err != nil {
		t.Fatal(err)
	}

	cases := []struct{ rel, reason string }{
		{"old.avi", "unsupported_format"},
		{"note.mp4", "unsupported_format"},
		{"cut.mp4", "damaged"},
	}
	for _, c := range cases {
		t.Run(c.rel, func(t *testing.T) {
			query := "?relPath=" + c.rel + "&serial=" + testSerial
			responses := map[string]func() (int, []byte){
				"metadata": func() (int, []byte) {
					w := h.get("/api/v0/videos/metadata" + query)
					return w.Code, w.Body.Bytes()
				},
				"formats": func() (int, []byte) {
					w := h.get("/api/v0/videos/transcode/formats" + query)
					return w.Code, w.Body.Bytes()
				},
				"trim": func() (int, []byte) {
					w := h.trim(fmt.Sprintf(`{"relPath":%q,"serial":%q,"startMs":0,"endMs":1000}`, c.rel, testSerial))
					return w.Code, w.Body.Bytes()
				},
				"transcode": func() (int, []byte) {
					w := h.post(transcodeBody(c.rel, "mkv", "original"))
					return w.Code, w.Body.Bytes()
				},
			}
			for name, do := range responses {
				code, body := do()
				if got := refusalOf(t, code, body).Reason; got != c.reason {
					t.Errorf("%s: reason %q, want %q (%s)", name, got, c.reason, body)
				}
			}
		})
	}
}

// TestTrimNamesWhyItCannotCut is the trim column of #3423: a fragmented MP4
// and an MPEG-TS file are both refused, and the reason tells them apart.
func TestTrimNamesWhyItCannotCut(t *testing.T) {
	h := newHarness(t)
	copyFixture(t, fragmentedFixture, filepath.Join(h.filesDir, "frag.mp4"))
	copyFixture(t, tsFixture, filepath.Join(h.filesDir, "clip.ts"))
	for rel, reason := range map[string]string{"frag.mp4": "fragmented", "clip.ts": "cannot_trim"} {
		w := h.trim(fmt.Sprintf(`{"relPath":%q,"serial":%q,"startMs":0,"endMs":1000}`, rel, testSerial))
		if got := refusalOf(t, w.Code, w.Body.Bytes()).Reason; got != reason {
			t.Errorf("trim %s: reason %q, want %q", rel, got, reason)
		}
	}
}
