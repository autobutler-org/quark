package derivativeutil_test

import (
	"bytes"
	"errors"
	"image"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func jpegBytes(t *testing.T, w, h int) []byte {
	t.Helper()
	var buf bytes.Buffer
	require.NoError(t, jpeg.Encode(&buf, image.NewRGBA(image.Rect(0, 0, w, h)), nil))
	return buf.Bytes()
}

func writeSource(t *testing.T, path string) {
	t.Helper()
	require.NoError(t, os.MkdirAll(filepath.Dir(path), 0o755))
	require.NoError(t, os.WriteFile(path, []byte("media"), 0o600))
}

func store(t *testing.T, source string, kind derivativeutil.Kind) {
	t.Helper()
	_, err := derivativeutil.Store(derivativeutil.StoreParams{
		SourcePath: source,
		Kind:       kind,
		Reader:     bytes.NewReader(jpegBytes(t, 400, 300)),
	})
	require.NoError(t, err)
}

func lookup(t *testing.T, source string, kind derivativeutil.Kind) derivativeutil.LookupResult {
	t.Helper()
	info, err := os.Stat(source)
	require.NoError(t, err)
	result, err := derivativeutil.Lookup(derivativeutil.LookupParams{
		SourcePath: source, Kind: kind, SourceModTime: info.ModTime(),
	})
	require.NoError(t, err)
	return result
}

func TestPathSitsInHiddenSiblingDirectory(t *testing.T) {
	got := derivativeutil.Path(filepath.Join("/files", "a", "b.heic"), derivativeutil.KindThumbnail)
	assert.Equal(t, filepath.Join("/files", "a", derivativeutil.DirName, "b.heic", "thumbnail.jpg"), got)
}

func TestStoreThenLookup(t *testing.T) {
	source := filepath.Join(t.TempDir(), "a", "clip.mov")
	writeSource(t, source)

	assert.False(t, lookup(t, source, derivativeutil.KindThumbnail).Found)
	store(t, source, derivativeutil.KindThumbnail)

	got := lookup(t, source, derivativeutil.KindThumbnail)
	require.True(t, got.Found)
	assert.Equal(t, derivativeutil.Path(source, derivativeutil.KindThumbnail), got.Path)
	assert.False(t, lookup(t, source, derivativeutil.KindPreview).Found)
}

func TestLookupIgnoresDerivativeOlderThanSource(t *testing.T) {
	source := filepath.Join(t.TempDir(), "photo.heic")
	writeSource(t, source)
	store(t, source, derivativeutil.KindThumbnail)

	// The file was rewritten after its thumbnail: the thumbnail shows the old
	// content, so it must not be served.
	later := time.Now().Add(time.Hour)
	require.NoError(t, os.Chtimes(source, later, later))
	assert.False(t, lookup(t, source, derivativeutil.KindThumbnail).Found)
}

func TestStoreRejectsNonJPEG(t *testing.T) {
	source := filepath.Join(t.TempDir(), "photo.heic")
	writeSource(t, source)

	var pngBuf bytes.Buffer
	require.NoError(t, png.Encode(&pngBuf, image.NewRGBA(image.Rect(0, 0, 4, 4))))
	for name, body := range map[string][]byte{
		"png":     pngBuf.Bytes(),
		"garbage": []byte("not an image"),
		"huge":    jpegBytes(t, 4000, 10),
	} {
		t.Run(name, func(t *testing.T) {
			_, err := derivativeutil.Store(derivativeutil.StoreParams{
				SourcePath: source, Kind: derivativeutil.KindThumbnail, Reader: bytes.NewReader(body),
			})
			assert.True(t, errors.Is(err, derivativeutil.ErrInvalid), "got %v", err)
			assert.False(t, lookup(t, source, derivativeutil.KindThumbnail).Found)
		})
	}
}

func TestStoreRejectsOversizedBody(t *testing.T) {
	source := filepath.Join(t.TempDir(), "photo.heic")
	writeSource(t, source)
	body := append(jpegBytes(t, 10, 10), bytes.Repeat([]byte{0}, int(derivativeutil.MaxBytes(derivativeutil.KindThumbnail)))...)
	_, err := derivativeutil.Store(derivativeutil.StoreParams{
		SourcePath: source, Kind: derivativeutil.KindThumbnail, Reader: bytes.NewReader(body),
	})
	assert.True(t, errors.Is(err, derivativeutil.ErrInvalid), "got %v", err)
}

func TestMoveCarriesDerivativesAndPrunesEmptyDir(t *testing.T) {
	root := t.TempDir()
	oldSource := filepath.Join(root, "a", "clip.mov")
	newSource := filepath.Join(root, "b", "renamed.mov")
	writeSource(t, oldSource)
	store(t, oldSource, derivativeutil.KindThumbnail)
	store(t, oldSource, derivativeutil.KindPreview)
	require.NoError(t, os.MkdirAll(filepath.Dir(newSource), 0o755))
	require.NoError(t, os.Rename(oldSource, newSource))

	require.NoError(t, derivativeutil.Move(oldSource, newSource))

	assert.True(t, lookup(t, newSource, derivativeutil.KindThumbnail).Found)
	assert.True(t, lookup(t, newSource, derivativeutil.KindPreview).Found)
	_, err := os.Stat(filepath.Join(root, "a", derivativeutil.DirName))
	assert.True(t, os.IsNotExist(err), "the emptied derivative directory should be removed")
}

func TestMoveDropsStaleDerivativesAtDestination(t *testing.T) {
	root := t.TempDir()
	oldSource := filepath.Join(root, "new.jpg")
	newSource := filepath.Join(root, "old.jpg")
	writeSource(t, oldSource)
	writeSource(t, newSource)
	store(t, newSource, derivativeutil.KindThumbnail)

	// oldSource has no derivatives; moving it over newSource replaces the
	// file, so newSource's thumbnail no longer describes it.
	require.NoError(t, os.Rename(oldSource, newSource))
	require.NoError(t, derivativeutil.Move(oldSource, newSource))
	assert.False(t, lookup(t, newSource, derivativeutil.KindThumbnail).Found)
}

func TestMoveWithoutDerivativesIsANoop(t *testing.T) {
	root := t.TempDir()
	require.NoError(t, derivativeutil.Move(filepath.Join(root, "a"), filepath.Join(root, "b")))
	entries, err := os.ReadDir(root)
	require.NoError(t, err)
	assert.Empty(t, entries)
}

func TestCopyDuplicatesDerivatives(t *testing.T) {
	root := t.TempDir()
	src := filepath.Join(root, "clip.mov")
	dst := filepath.Join(root, "sub", "clip_copy.mov")
	writeSource(t, src)
	store(t, src, derivativeutil.KindThumbnail)
	writeSource(t, dst)

	require.NoError(t, derivativeutil.Copy(src, dst))

	assert.True(t, lookup(t, src, derivativeutil.KindThumbnail).Found)
	assert.True(t, lookup(t, dst, derivativeutil.KindThumbnail).Found)
}

func TestRemoveDeletesDerivatives(t *testing.T) {
	root := t.TempDir()
	source := filepath.Join(root, "clip.mov")
	writeSource(t, source)
	store(t, source, derivativeutil.KindThumbnail)

	require.NoError(t, derivativeutil.Remove(source))
	_, err := os.Stat(filepath.Join(root, derivativeutil.DirName))
	assert.True(t, os.IsNotExist(err))
	require.NoError(t, derivativeutil.Remove(source), "removing twice is fine")
}

func TestParseKind(t *testing.T) {
	for _, raw := range []string{"thumbnail", "preview"} {
		kind, ok := derivativeutil.ParseKind(raw)
		assert.True(t, ok)
		assert.Equal(t, raw, string(kind))
	}
	_, ok := derivativeutil.ParseKind("../../etc")
	assert.False(t, ok)
	assert.False(t, strings.Contains(derivativeutil.DirName, "/"))
}
