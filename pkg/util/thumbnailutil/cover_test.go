package thumbnailutil

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/musicutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// coverImage is a w×h image of one color, encoded as JPEG or PNG.
func coverImage(t *testing.T, w, h int, c color.Color, asPNG bool) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := range h {
		for x := range w {
			img.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	var err error
	if asPNG {
		err = png.Encode(&buf, img)
	} else {
		err = jpeg.Encode(&buf, img, nil)
	}
	if err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// coverFLAC is a short FLAC file titled title, embedding picture as its front
// cover when picture is not nil.
func coverFLAC(title string, picture []byte) []byte {
	cat := func(parts ...[]byte) []byte { return bytes.Join(parts, nil) }
	be32 := func(n uint32) []byte { return binary.BigEndian.AppendUint32(nil, n) }
	le32 := func(n uint32) []byte { return binary.LittleEndian.AppendUint32(nil, n) }
	block := func(typ byte, last bool, body []byte) []byte {
		if last {
			typ |= 0x80
		}
		return cat([]byte{typ, byte(len(body) >> 16), byte(len(body) >> 8), byte(len(body))}, body)
	}
	const rate = 44100
	info := make([]byte, 34)
	binary.BigEndian.PutUint64(info[10:18], uint64(rate)<<44|uint64(1)<<41|uint64(15)<<36|10*rate)
	comment := "TITLE=" + title
	vc := cat(le32(4), []byte("test"), le32(1), le32(uint32(len(comment))), []byte(comment))
	out := cat([]byte("fLaC"), block(0, false, info), block(4, picture == nil, vc))
	if picture != nil {
		mime := "image/jpeg"
		pic := cat(be32(3), be32(uint32(len(mime))), []byte(mime), be32(0), make([]byte, 16), be32(uint32(len(picture))), picture)
		out = cat(out, block(6, true, pic))
	}
	return append(out, make([]byte, 64)...)
}

// library is a namespace holding files, each audio file indexed into a fresh
// music library, and the cache directory under a temporary HOME.
func library(t *testing.T, files map[string][]byte) (vfs.VFS, db.Querier) {
	t.Helper()
	t.Setenv("HOME", t.TempDir())
	ctx := context.Background()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for p, data := range files {
		if dir := path.Dir(p); dir != "." {
			if err := fsys.MkdirAll(ctx, dir); err != nil {
				t.Fatal(err)
			}
		}
		if err := fsys.Write(ctx, p, bytes.NewReader(data), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	database := dbtest.NewDB(t)
	for p := range files {
		if !musicutil.IsAudioPath(p) {
			continue
		}
		if _, err := musicutil.IndexTrack(musicutil.IndexTrackParams{Ctx: ctx, DB: database.Db, FS: fsys, RelPath: p}); err != nil {
			t.Fatalf("index %s: %v", p, err)
		}
	}
	return fsys, database.Queries
}

func prepareCover(t *testing.T, queries db.Querier, relPath string, size Size) (PrepareCoverResult, error) {
	t.Helper()
	return PrepareCover(PrepareCoverParams{Ctx: context.Background(), Queries: queries, RelPath: relPath, Size: size})
}

func generateCover(fsys vfs.VFS, relPath string, prepared PrepareCoverResult) (GenerateResult, error) {
	return GenerateCover(GenerateCoverParams{
		Ctx: context.Background(), FS: fsys, RelPath: relPath,
		CoverSource: prepared.CoverSource, CoverKey: prepared.CoverKey,
		Width: prepared.Width, Height: prepared.Height, CachedPath: prepared.CachedPath,
	})
}

// assertJPEG fails unless the cache entry at cachedPath is a w×h JPEG.
func assertJPEG(t *testing.T, cachedPath string, w, h int) {
	t.Helper()
	f, err := os.Open(cachedPath)
	if err != nil {
		t.Fatalf("cache entry not committed: %v", err)
	}
	defer f.Close()
	cfg, format, err := image.DecodeConfig(f)
	if err != nil {
		t.Fatalf("cache entry is not an image: %v", err)
	}
	if format != "jpeg" || cfg.Width != w || cfg.Height != h {
		t.Errorf("cache entry is a %dx%d %s, want a %dx%d jpeg", cfg.Width, cfg.Height, format, w, h)
	}
}

// TestCoverEmbeddedSharedByAlbum: tracks embedding the same picture share one
// cache entry per size, keyed by the picture and not by either track's path,
// so the second track is a hit without reading anything.
func TestCoverEmbeddedSharedByAlbum(t *testing.T) {
	art := coverImage(t, 300, 300, color.RGBA{R: 200, A: 255}, false)
	fsys, queries := library(t, map[string][]byte{
		"Album/01.flac":       coverFLAC("one", art),
		"Album/02.flac":       coverFLAC("two", art),
		"Elsewhere/solo.flac": coverFLAC("solo", art),
	})

	first, err := prepareCover(t, queries, "Album/01.flac", SizeSm)
	if err != nil {
		t.Fatal(err)
	}
	if first.Hit || first.CoverSource != "embedded" {
		t.Fatalf("first PrepareCover = %+v, want a miss on an embedded cover", first)
	}
	if _, err := generateCover(fsys, "Album/01.flac", first); err != nil {
		t.Fatalf("GenerateCover: %v", err)
	}
	assertJPEG(t, first.CachedPath, 96, 96)

	for _, other := range []string{"Album/02.flac", "Elsewhere/solo.flac"} {
		prepared, err := prepareCover(t, queries, other, SizeSm)
		if err != nil {
			t.Fatal(err)
		}
		if prepared.CachedPath != first.CachedPath || !prepared.Hit {
			t.Errorf("%s: PrepareCover = %+v, want a hit on %s", other, prepared, first.CachedPath)
		}
	}

	larger, err := prepareCover(t, queries, "Album/02.flac", SizeMd)
	if err != nil {
		t.Fatal(err)
	}
	if larger.CachedPath == first.CachedPath || larger.Hit {
		t.Errorf("md PrepareCover = %+v, want its own entry, not yet generated", larger)
	}
}

// TestCoverFromFolder: a track with no embedded picture takes the cover image
// in its folder, a PNG here, and caches it as a JPEG.
func TestCoverFromFolder(t *testing.T) {
	fsys, queries := library(t, map[string][]byte{
		"Album/01.flac":   coverFLAC("one", nil),
		"Album/Cover.PNG": coverImage(t, 500, 400, color.RGBA{G: 200, A: 255}, true),
	})
	prepared, err := prepareCover(t, queries, "Album/01.flac", SizeMd)
	if err != nil {
		t.Fatal(err)
	}
	if prepared.CoverSource != "folder:Cover.PNG" {
		t.Fatalf("CoverSource = %q, want folder:Cover.PNG", prepared.CoverSource)
	}
	if _, err := generateCover(fsys, "Album/01.flac", prepared); err != nil {
		t.Fatalf("GenerateCover: %v", err)
	}
	assertJPEG(t, prepared.CachedPath, 240, 240)
}

// TestCoverEmbeddedBeforeFolder: the embedded picture wins over the folder's,
// since compilations are where folder art is wrong.
func TestCoverEmbeddedBeforeFolder(t *testing.T) {
	_, queries := library(t, map[string][]byte{
		"Mix/01.flac":    coverFLAC("one", coverImage(t, 50, 50, color.White, false)),
		"Mix/folder.jpg": coverImage(t, 50, 50, color.Black, false),
	})
	prepared, err := prepareCover(t, queries, "Mix/01.flac", SizeSm)
	if err != nil {
		t.Fatal(err)
	}
	if prepared.CoverSource != "embedded" {
		t.Errorf("CoverSource = %q, want embedded", prepared.CoverSource)
	}
}

// TestCoverNone: a track with no cover, and a path the library has no row
// for, are both ErrNoCover.
func TestCoverNone(t *testing.T) {
	_, queries := library(t, map[string][]byte{"Album/01.flac": coverFLAC("one", nil)})
	for _, relPath := range []string{"Album/01.flac", "Album/missing.flac"} {
		if _, err := prepareCover(t, queries, relPath, SizeSm); !errors.Is(err, ErrNoCover) {
			t.Errorf("PrepareCover(%s) = %v, want ErrNoCover", relPath, err)
		}
	}
}

// TestCoverChangedSinceScan: a folder image replaced after the scan no longer
// hashes to the key other tracks share, so nothing is cached under that key.
func TestCoverChangedSinceScan(t *testing.T) {
	fsys, queries := library(t, map[string][]byte{
		"Album/01.flac":   coverFLAC("one", nil),
		"Album/cover.jpg": coverImage(t, 50, 50, color.White, false),
	})
	prepared, err := prepareCover(t, queries, "Album/01.flac", SizeSm)
	if err != nil {
		t.Fatal(err)
	}
	replaced := coverImage(t, 60, 60, color.Black, false)
	if err := fsys.Write(context.Background(), "Album/cover.jpg", bytes.NewReader(replaced), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if _, err := generateCover(fsys, "Album/01.flac", prepared); !errors.Is(err, ErrNoCover) {
		t.Errorf("GenerateCover = %v, want ErrNoCover", err)
	}
	if _, err := os.Stat(prepared.CachedPath); !os.IsNotExist(err) {
		t.Errorf("a changed cover must not be cached under the old key: %v", err)
	}
}
