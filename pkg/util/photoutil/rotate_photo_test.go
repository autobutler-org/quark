package photoutil_test

import (
	"bytes"
	"context"
	"errors"
	"image"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// orientationOf reads the EXIF orientation back out of stored JPEG bytes.
func orientationOf(t *testing.T, data []byte) int {
	t.Helper()
	return photoutil.GetOrientation(bytes.NewReader(data), photoutil.ImageFormatFromPath("a.jpg"))
}

func rotateRegistry(t *testing.T, files map[string][]byte) (vfs.Registry, *vfs.MemVFS) {
	t.Helper()
	mem := vfs.NewMemVFS(vfs.FilesNamespace(""))
	for p, data := range files {
		if err := mem.Write(context.Background(), p, bytes.NewReader(data), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, mem); err != nil {
		t.Fatal(err)
	}
	return registry, mem
}

func readStored(t *testing.T, fsys vfs.VFS, p string) []byte {
	t.Helper()
	f, err := fsys.Open(context.Background(), p)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	var buf bytes.Buffer
	if _, err := buf.ReadFrom(f); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func TestNextOrientation(t *testing.T) {
	// A quarter turn clockwise walks 1 -> 6 -> 3 -> 8 and, mirrored,
	// 2 -> 7 -> 4 -> 5.
	cases := []struct {
		from, quarters, want int
	}{
		{1, 1, 6}, {1, 2, 3}, {1, 3, 8}, {1, 0, 1}, {1, 4, 1}, {1, -1, 8},
		{6, 1, 3}, {8, 1, 1},
		{2, 1, 7}, {7, 1, 4}, {4, 1, 5}, {5, 1, 2}, {2, 2, 4}, {2, 3, 5},
		{0, 1, 6}, {9, 1, 6}, // an invalid tag reads as upright
	}
	for _, c := range cases {
		if got := photoutil.NextOrientation(c.from, int64(c.quarters)); got != c.want {
			t.Errorf("NextOrientation(%d, %d) = %d, want %d", c.from, c.quarters, got, c.want)
		}
	}
}

func TestRotatePhoto_PatchesTagInPlace(t *testing.T) {
	src := rotatedWithTag(t, image.NewRGBA(image.Rect(0, 0, 8, 6))) // orientation 6
	registry, mem := rotateRegistry(t, map[string][]byte{"a.jpg": src})
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	defer unsubscribe()

	res, err := photoutil.RotatePhoto(photoutil.RotatePhotoParams{
		Ctx: context.Background(), Registry: registry, EventBus: bus, RelPath: "a.jpg", Quarters: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	if res.Orientation != 3 {
		t.Errorf("result orientation = %d, want 3", res.Orientation)
	}
	got := readStored(t, mem, "a.jpg")
	if o := orientationOf(t, got); o != 3 {
		t.Errorf("stored orientation = %d, want 3", o)
	}
	if len(got) != len(src) {
		t.Errorf("size changed from %d to %d; the tag should be patched in place", len(src), len(got))
	}
	select {
	case ev := <-events:
		if ev.Path != "a.jpg" {
			t.Errorf("event path = %q, want a.jpg", ev.Path)
		}
	case <-time.After(time.Second):
		t.Error("no event published")
	}
}

func TestRotatePhoto_InsertsExifWhenMissing(t *testing.T) {
	src := encodeJPEG(t, image.NewRGBA(image.Rect(0, 0, 8, 6)), 90)
	registry, mem := rotateRegistry(t, map[string][]byte{"a.jpeg": src})
	params := photoutil.RotatePhotoParams{Ctx: context.Background(), Registry: registry, RelPath: "a.jpeg", Quarters: 1}

	res, err := photoutil.RotatePhoto(params)
	if err != nil {
		t.Fatal(err)
	}
	if res.Orientation != 6 {
		t.Errorf("result orientation = %d, want 6", res.Orientation)
	}
	got := readStored(t, mem, "a.jpeg")
	if o := orientationOf(t, got); o != 6 {
		t.Errorf("stored orientation = %d, want 6", o)
	}
	if _, _, err := image.Decode(bytes.NewReader(got)); err != nil {
		t.Errorf("rotated file no longer decodes: %v", err)
	}
	// The rest of the file is untouched: rotating is lossless.
	if !bytes.HasSuffix(got, src[2:]) {
		t.Error("image data after the inserted segment differs from the original")
	}

	// A second turn now finds the tag and patches it.
	if _, err := photoutil.RotatePhoto(params); err != nil {
		t.Fatal(err)
	}
	if o := orientationOf(t, readStored(t, mem, "a.jpeg")); o != 3 {
		t.Errorf("second turn orientation = %d, want 3", o)
	}
}

func TestRotatePhoto_FullTurnWritesNothing(t *testing.T) {
	src := encodeJPEG(t, image.NewRGBA(image.Rect(0, 0, 8, 6)), 90)
	registry, mem := rotateRegistry(t, map[string][]byte{"a.jpg": src})
	res, err := photoutil.RotatePhoto(photoutil.RotatePhotoParams{
		Ctx: context.Background(), Registry: registry, RelPath: "a.jpg", Quarters: 4,
	})
	if err != nil || res.Orientation != 1 {
		t.Fatalf("got %+v, %v; want orientation 1", res, err)
	}
	if !bytes.Equal(readStored(t, mem, "a.jpg"), src) {
		t.Error("a full turn changed the file")
	}
}

func TestRotatePhoto_UnsupportedFormats(t *testing.T) {
	registry, _ := rotateRegistry(t, map[string][]byte{
		"a.heic": []byte("x"), "a.png": []byte("x"), "a.webp": []byte("x"), "a.gif": []byte("x"),
		"fake.jpg": []byte("not a jpeg"),
	})
	for _, name := range []string{"a.heic", "a.png", "a.webp", "a.gif", "fake.jpg"} {
		_, err := photoutil.RotatePhoto(photoutil.RotatePhotoParams{
			Ctx: context.Background(), Registry: registry, RelPath: name, Quarters: 1,
		})
		if !errors.Is(err, photoutil.ErrRotationUnsupported) {
			t.Errorf("%s: err = %v, want ErrRotationUnsupported", name, err)
		}
	}
}

func TestRotatePhoto_Missing(t *testing.T) {
	registry, _ := rotateRegistry(t, nil)
	_, err := photoutil.RotatePhoto(photoutil.RotatePhotoParams{
		Ctx: context.Background(), Registry: registry, RelPath: "nope.jpg", Quarters: 1,
	})
	if !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("err = %v, want vfs.ErrNotFound", err)
	}
}
