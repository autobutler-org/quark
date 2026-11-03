package frame_test

import (
	"encoding/json"
	"os"
	"os/exec"
	"testing"
)

// nodeEval runs a snippet against the real frame.js under Node, which exports the page's pure helpers, and returns
// what the snippet printed as JSON. It skips the test when Node is not installed.
func nodeEval(t *testing.T, snippet string) json.RawMessage {
	t.Helper()
	node, err := exec.LookPath("node")
	if err != nil {
		t.Skip("node is not installed")
	}
	if _, err := os.Stat("assets/frame.js"); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command(node, "-e", "const frame = require('./assets/frame.js');"+snippet).Output()
	if err != nil {
		t.Fatalf("node failed: %v\n%s", err, out)
	}
	return json.RawMessage(out)
}

func TestWhichPhotosThePageShows(t *testing.T) {
	out := nodeEval(t, `
const cases = {
  'a.jpg': 1, 'a.JPEG': 1, 'a.png': 1, 'a.webp': 1, 'a.gif': 1, 'a.heic': 1, 'a.HEIF': 1, 'raw/a.dng': 1, 'a.nef': 1,
  'a.mp4': 0, 'a.mov': 0, 'a.pdf': 0, 'a.txt': 0, 'a': 0, 'jpg': 0, 'a.jpg.zip': 0,
};
const got = {};
for (const name of Object.keys(cases)) got[name] = frame.playable({ relPath: name }) ? 1 : 0;
got['null'] = frame.playable(null) ? 1 : 0;
got['no path'] = frame.playable({}) ? 1 : 0;
process.stdout.write(JSON.stringify({ got, cases }));`)
	var res struct {
		Got   map[string]int `json:"got"`
		Cases map[string]int `json:"cases"`
	}
	if err := json.Unmarshal(out, &res); err != nil {
		t.Fatal(err)
	}
	for name, want := range res.Cases {
		if res.Got[name] != want {
			t.Errorf("playable(%q) = %d, want %d", name, res.Got[name], want)
		}
	}
	if res.Got["null"] != 0 || res.Got["no path"] != 0 {
		t.Errorf("an item with no path counted as playable: %v", res.Got)
	}
}

func TestPhotoAddresses(t *testing.T) {
	out := nodeEval(t, `
process.stdout.write(JSON.stringify([
  frame.photoUrl({ relPath: 'users/ann/a b&c.jpg', deviceSerial: '' }),
  frame.photoUrl({ relPath: 'Camera/IMG_1.HEIC', deviceSerial: 'ABC 1' }),
  frame.photoUrl({ relPath: 'x/ü.png', deviceSerial: 'S' }),
  frame.photoUrl({ relPath: 'raw/a.dng', deviceSerial: '' }),
]));`)
	var got []string
	if err := json.Unmarshal(out, &got); err != nil {
		t.Fatal(err)
	}
	// A slash in a query value travels as %2F.
	const slash = "%2F"
	want := []string{
		"/api/v0/files/download?filePath=users" + slash + "ann" + slash + "a%20b%26c.jpg",
		// The Quark does not decode HEIC, so the frame shows its stored thumbnail (#2382).
		"/api/v0/thumbnails/Camera/IMG_1.HEIC?size=lg&serial=ABC%201",
		"/api/v0/files/download?filePath=x" + slash + "%C3%BC.png&serial=S",
		"/api/v0/files/download?filePath=raw" + slash + "a.dng&format=jpeg",
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("address %d = %s, want %s", i, got[i], want[i])
		}
	}
}

func TestShuffleKeepsEveryPhotoOnce(t *testing.T) {
	out := nodeEval(t, `
const list = []; for (let i = 0; i < 500; i++) list.push(i);
const mixed = frame.shuffled(list);
const same = mixed.slice().sort((a, b) => a - b).every((v, i) => v === i);
process.stdout.write(JSON.stringify({ same, moved: mixed.some((v, i) => v !== i), untouched: list.every((v, i) => v === i), n: mixed.length }));`)
	var got struct {
		Same, Moved, Untouched bool
		N                      int
	}
	if err := json.Unmarshal(out, &got); err != nil {
		t.Fatal(err)
	}
	if !got.Same || got.N != 500 {
		t.Errorf("a shuffle lost or repeated photos: %+v", got)
	}
	if !got.Moved {
		t.Error("a shuffle of 500 photos changed nothing")
	}
	if !got.Untouched {
		t.Error("shuffled changed the list it was given")
	}
}
