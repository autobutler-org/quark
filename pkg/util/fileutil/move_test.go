package fileutil_test

import (
	"context"
	"io"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// A move that replaces a file runs BeforeOverwrite while the old content is
// still there (#2992). A move to a free name, or onto a folder, does not.
func TestMoveFileRunsBeforeOverwriteOnlyWhenReplacingAFile(t *testing.T) {
	ctx := context.Background()
	fsys := vfs.NewMemVFS(vfs.FilesNamespace(""))
	registry := vfs.NewRegistry()
	if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace("")}, fsys); err != nil {
		t.Fatal(err)
	}
	for p, content := range map[string]string{"a.qslide": "moved", "b.qslide": "replaced", "c.qslide": "renamed"} {
		if err := fsys.Write(ctx, p, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	if err := fsys.MkdirAll(ctx, "folder"); err != nil {
		t.Fatal(err)
	}

	var seen []string
	for _, move := range [][2]string{{"a.qslide", "b.qslide"}, {"c.qslide", "free.qslide"}, {"free.qslide", "folder"}} {
		// A move onto a folder may be refused; only the hook matters here.
		_, _ = fileutil.MoveFile(fileutil.MoveFileParams{
			Ctx: ctx, Registry: registry, EventBus: eventbus.New(),
			OldFilePath: move[0], NewFilePath: move[1],
			BeforeOverwrite: func(p string) {
				rc, err := fsys.Open(ctx, p)
				if err != nil {
					t.Fatalf("open %s in the hook: %v", p, err)
				}
				defer func() { _ = rc.Close() }()
				old, _ := io.ReadAll(rc)
				seen = append(seen, p+"="+string(old))
			},
		})
	}
	if want := []string{"b.qslide=replaced"}; !slices.Equal(seen, want) {
		t.Errorf("BeforeOverwrite saw %q, want %q", seen, want)
	}
}

func TestMoveFileCarriesDocumentMediaMarkerAcrossDevices(t *testing.T) {
	ctx := context.Background()
	registry := vfs.NewRegistry()
	devices := map[string]*vfs.MemVFS{
		"":    vfs.NewMemVFS(vfs.FilesNamespace("")),
		"USB": vfs.NewMemVFS(vfs.FilesNamespace("USB")),
	}
	for serial, fsys := range devices {
		if err := registry.Register(vfs.Namespace{ID: vfs.FilesNamespace(serial)}, fsys); err != nil {
			t.Fatal(err)
		}
	}
	if err := devices[""].Write(ctx, "Talk_media/image.png", strings.NewReader("picture"), vfs.WriteOptions{}); err != nil {
		t.Fatal(err)
	}
	if err := photoutil.MarkDocumentMedia(ctx, devices[""], "Talk_media"); err != nil {
		t.Fatal(err)
	}
	if _, err := fileutil.MoveFile(fileutil.MoveFileParams{
		Ctx: ctx, Registry: registry, EventBus: eventbus.New(),
		OldFilePath: "Talk_media", NewFilePath: "archive/assets",
		NewDeviceSerial: "USB",
	}); err != nil {
		t.Fatal(err)
	}
	if !photoutil.IsDocumentMedia(ctx, devices["USB"], "archive/assets/image.png") {
		t.Fatal("moved media lost its document ownership marker")
	}
}
