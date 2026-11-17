package photoutil_test

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/photoutil"
)

// TestOpenMapTile opens a tile inside the pack and refuses every z/x/y that
// is not a plain in-range tile number, so no request names a file outside it.
func TestOpenMapTile(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "0", "0"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "0", "0", "0.png"), []byte("tile"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "secret.png"), []byte("no"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := photoutil.OpenMapTile(photoutil.OpenMapTileParams{Dir: dir, Z: "0", X: "0", Y: "0"})
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(got.Reader)
	_ = got.Reader.Close()
	if string(body) != "tile" || got.Size != 4 {
		t.Errorf("tile = %q (%d bytes)", body, got.Size)
	}
	for _, tc := range [][3]string{
		{"0", "0", "1"}, {"0", "1", "0"}, {"1", "0", "0"}, {"20", "0", "0"},
		{"-1", "0", "0"}, {"0", "..", "secret"}, {"0x0", "0", "0"}, {"", "0", "0"},
	} {
		_, err := photoutil.OpenMapTile(photoutil.OpenMapTileParams{Dir: dir, Z: tc[0], X: tc[1], Y: tc[2]})
		if !errors.Is(err, photoutil.ErrNoMapTile) {
			t.Errorf("%v: err = %v, want ErrNoMapTile", tc, err)
		}
	}
}
