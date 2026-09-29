package avatarutil_test

import (
	"bytes"
	"encoding/binary"
	"errors"
	"hash/crc32"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/avatarutil"
)

// pngHeader is the signature and IHDR of a PNG declaring w x h pixels, with
// no image data: enough for DecodeConfig, which is all a bomb needs to pass.
func pngHeader(w, h uint32) []byte {
	ihdr := make([]byte, 13)
	binary.BigEndian.PutUint32(ihdr[0:], w)
	binary.BigEndian.PutUint32(ihdr[4:], h)
	ihdr[8], ihdr[9] = 8, 6 // 8-bit RGBA
	chunk := append([]byte("IHDR"), ihdr...)
	out := []byte("\x89PNG\r\n\x1a\n")
	out = binary.BigEndian.AppendUint32(out, 13)
	out = append(out, chunk...)
	return binary.BigEndian.AppendUint32(out, crc32.ChecksumIEEE(chunk))
}

func TestSave_RefusesDecompressionBomb(t *testing.T) {
	dataDir := t.TempDir()
	_, err := avatarutil.Save(avatarutil.SaveParams{
		DataDir: dataDir,
		UserID:  1,
		Source:  bytes.NewReader(pngHeader(20000, 20000)),
	})
	if !errors.Is(err, avatarutil.ErrNotImage) {
		t.Fatalf("Save of a 400-megapixel PNG = %v, want ErrNotImage", err)
	}
	if _, err := os.Stat(filepath.Join(avatarutil.Dir(dataDir), "1.png")); !os.IsNotExist(err) {
		t.Error("a refused upload was stored")
	}
}

func TestRemoveAll(t *testing.T) {
	dataDir := t.TempDir()
	dir := avatarutil.Dir(dataDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "3.jpg"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := avatarutil.RemoveAll(avatarutil.RemoveAllParams{DataDir: dataDir}); err != nil {
		t.Fatal(err)
	}
	stat, err := avatarutil.Stat(avatarutil.StatParams{DataDir: dataDir, UserID: 3})
	if err != nil || stat.Exists {
		t.Errorf("Stat after RemoveAll = %+v, %v", stat, err)
	}
}
