package vfs_test

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/vfs"
)

func makeLocalVFS(t *testing.T, namespaceID string) vfs.VFS {
	t.Helper()
	dir := t.TempDir()
	v, err := vfs.NewLocalVFS(dir, namespaceID)
	if err != nil {
		t.Fatalf("NewLocalVFS: %v", err)
	}
	return v
}

func makeMemVFS(t *testing.T, namespaceID string) vfs.VFS {
	t.Helper()
	return vfs.NewMemVFS(namespaceID)
}

type vfsFactory struct {
	name string
	make func(t *testing.T, ns string) vfs.VFS
}

var factories = []vfsFactory{
	{"LocalVFS", makeLocalVFS},
	{"MemVFS", makeMemVFS},
}

func TestWriteAndStat(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			content := "hello vfs"
			if err := v.Write(ctx, "test.txt", strings.NewReader(content), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			fi, err := v.Stat(ctx, "test.txt")
			if err != nil {
				t.Fatalf("Stat: %v", err)
			}
			if fi.Name != "test.txt" {
				t.Errorf("Name = %q, want test.txt", fi.Name)
			}
			if fi.Size != int64(len(content)) {
				t.Errorf("Size = %d, want %d", fi.Size, len(content))
			}
			if fi.IsDir {
				t.Error("IsDir should be false")
			}
			if fi.ContentHash == "" {
				t.Error("ContentHash should be non-empty")
			}
			if fi.Namespace != "test-ns" {
				t.Errorf("Namespace = %q, want test-ns", fi.Namespace)
			}
			if !strings.HasPrefix(fi.MimeType, "text/plain") {
				t.Errorf("MimeType = %q, expected text/plain prefix", fi.MimeType)
			}
		})
	}
}

func TestStatNotFound(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			_, err := v.Stat(ctx, "nonexistent.txt")
			if !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("expected ErrNotFound, got %v", err)
			}
		})
	}
}

func TestOpenAndReadContent(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			content := "read me back"
			if err := v.Write(ctx, "read.txt", strings.NewReader(content), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			rc, err := v.Open(ctx, "read.txt")
			if err != nil {
				t.Fatalf("Open: %v", err)
			}
			defer rc.Close()
			got, err := io.ReadAll(rc)
			if err != nil {
				t.Fatalf("ReadAll: %v", err)
			}
			if string(got) != content {
				t.Errorf("content = %q, want %q", got, content)
			}
		})
	}
}

func TestOpenNotFound(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			_, err := v.Open(ctx, "ghost.txt")
			if !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("expected ErrNotFound, got %v", err)
			}
		})
	}
}

func TestListFlat(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			for _, name := range []string{"a.txt", "b.txt", "c.txt"} {
				if err := v.Write(ctx, name, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
					t.Fatalf("Write %s: %v", name, err)
				}
			}
			infos, err := v.List(ctx, "", nil)
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			found := make(map[string]bool)
			for _, fi := range infos {
				found[fi.Name] = true
			}
			for _, name := range []string{"a.txt", "b.txt", "c.txt"} {
				if !found[name] {
					t.Errorf("expected %q in listing", name)
				}
			}
		})
	}
}

func TestListWithMaxResults(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			for _, name := range []string{"a.txt", "b.txt", "c.txt", "d.txt"} {
				if err := v.Write(ctx, name, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
					t.Fatalf("Write %s: %v", name, err)
				}
			}
			infos, err := v.List(ctx, "", &vfs.ListFilter{MaxResults: 2})
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			if len(infos) > 2 {
				t.Errorf("expected at most 2 results, got %d", len(infos))
			}
		})
	}
}

func TestListMimeFilter(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			fileMap := map[string]string{"doc.txt": "text", "img.png": "image", "page.txt": "text2"}
			for name, content := range fileMap {
				if err := v.Write(ctx, name, strings.NewReader(content), vfs.WriteOptions{}); err != nil {
					t.Fatalf("Write %s: %v", name, err)
				}
			}
			infos, err := v.List(ctx, "", &vfs.ListFilter{MimePrefix: "text/"})
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			for _, fi := range infos {
				if !fi.IsDir && !strings.HasPrefix(fi.MimeType, "text/") {
					t.Errorf("unexpected MIME %q for %q", fi.MimeType, fi.Name)
				}
			}
			found := make(map[string]bool)
			for _, fi := range infos {
				found[fi.Name] = true
			}
			if !found["doc.txt"] || !found["page.txt"] {
				t.Error("expected both .txt files in filtered listing")
			}
			if found["img.png"] {
				t.Error("did not expect img.png in text/ filtered listing")
			}
		})
	}
}

func TestListRecursive(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.MkdirAll(ctx, "sub/deep"); err != nil {
				t.Fatalf("MkdirAll: %v", err)
			}
			for _, p := range []string{"top.txt", "sub/mid.txt", "sub/deep/bottom.txt"} {
				if err := v.Write(ctx, p, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
					t.Fatalf("Write %s: %v", p, err)
				}
			}
			infos, err := v.List(ctx, "", &vfs.ListFilter{Recursive: true})
			if err != nil {
				t.Fatalf("List recursive: %v", err)
			}
			found := make(map[string]bool)
			for _, fi := range infos {
				found[fi.Path] = true
			}
			for _, expected := range []string{"top.txt", "sub/mid.txt", "sub/deep/bottom.txt"} {
				if !found[expected] {
					t.Errorf("expected %q in recursive listing", expected)
				}
			}
		})
	}
}

func TestListAfterPathCursor(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			for _, name := range []string{"a.txt", "b.txt", "c.txt"} {
				if err := v.Write(ctx, name, strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
					t.Fatalf("Write %s: %v", name, err)
				}
			}
			infos, err := v.List(ctx, "", &vfs.ListFilter{AfterPath: "a.txt"})
			if err != nil {
				t.Fatalf("List: %v", err)
			}
			for _, fi := range infos {
				if fi.Path <= "a.txt" {
					t.Errorf("cursor not respected: got path %q", fi.Path)
				}
			}
		})
	}
}

func TestDeleteFile(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.Write(ctx, "del.txt", strings.NewReader("bye"), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			if err := v.Delete(ctx, "del.txt", vfs.DeleteOptions{}); err != nil {
				t.Fatalf("Delete: %v", err)
			}
			_, err := v.Stat(ctx, "del.txt")
			if !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("expected ErrNotFound after delete, got %v", err)
			}
		})
	}
}

func TestDeleteNonEmptyDirWithoutRecursive(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.MkdirAll(ctx, "mydir"); err != nil {
				t.Fatalf("MkdirAll: %v", err)
			}
			if err := v.Write(ctx, "mydir/file.txt", strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			err := v.Delete(ctx, "mydir", vfs.DeleteOptions{Recursive: false})
			if !errors.Is(err, vfs.ErrNotEmpty) {
				t.Errorf("expected ErrNotEmpty, got %v", err)
			}
		})
	}
}

func TestDeleteDirWithRecursive(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.MkdirAll(ctx, "rmdir/sub"); err != nil {
				t.Fatalf("MkdirAll: %v", err)
			}
			if err := v.Write(ctx, "rmdir/sub/file.txt", strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			if err := v.Delete(ctx, "rmdir", vfs.DeleteOptions{Recursive: true}); err != nil {
				t.Fatalf("Delete recursive: %v", err)
			}
			_, err := v.Stat(ctx, "rmdir")
			if !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("expected ErrNotFound after recursive delete, got %v", err)
			}
		})
	}
}

func TestMkdirAll(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.MkdirAll(ctx, "a/b/c"); err != nil {
				t.Fatalf("MkdirAll: %v", err)
			}
			fi, err := v.Stat(ctx, "a/b/c")
			if err != nil {
				t.Fatalf("Stat after MkdirAll: %v", err)
			}
			if !fi.IsDir {
				t.Error("expected IsDir=true after MkdirAll")
			}
		})
	}
}

func TestWriteIfNoneMatchConflict(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.Write(ctx, "exists.txt", strings.NewReader("first"), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			err := v.Write(ctx, "exists.txt", strings.NewReader("second"), vfs.WriteOptions{IfNoneMatch: "*"})
			if !errors.Is(err, vfs.ErrConflict) {
				t.Errorf("expected ErrConflict, got %v", err)
			}
		})
	}
}

func TestWriteIfNoneMatchNewFile(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			err := v.Write(ctx, "newfile.txt", strings.NewReader("hello"), vfs.WriteOptions{IfNoneMatch: "*"})
			if err != nil {
				t.Errorf("expected success for new file with IfNoneMatch=*, got %v", err)
			}
		})
	}
}

func TestLocalVFSPathTraversal(t *testing.T) {
	dir := t.TempDir()
	v, err := vfs.NewLocalVFS(dir, "ns")
	if err != nil {
		t.Fatalf("NewLocalVFS: %v", err)
	}
	ctx := context.Background()
	// Attempt to escape root via ..
	_, err = v.Stat(ctx, "../etc/passwd")
	if !errors.Is(err, vfs.ErrPermissionDenied) {
		t.Errorf("expected ErrPermissionDenied for path traversal, got %v", err)
	}
}

func TestRegistryRegisterGetUnregister(t *testing.T) {
	reg := vfs.NewRegistry()
	ns := vfs.Namespace{ID: "ns1", PluginID: "plugin1", MountPath: "/ns1"}
	impl := vfs.NewMemVFS("ns1")
	if err := reg.Register(ns, impl); err != nil {
		t.Fatalf("Register: %v", err)
	}
	v, ok := reg.Get("ns1")
	if !ok {
		t.Fatal("Get: not found after Register")
	}
	if v != impl {
		t.Error("Get: returned wrong impl")
	}
	list := reg.List("")
	if len(list) != 1 {
		t.Errorf("List: expected 1, got %d", len(list))
	}
	reg.Unregister("ns1")
	_, ok = reg.Get("ns1")
	if ok {
		t.Error("Get: expected not found after Unregister")
	}
}

func TestMoveFile(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.Write(ctx, "src.txt", strings.NewReader("move me"), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			if err := v.Move(ctx, "src.txt", "dst.txt"); err != nil {
				t.Fatalf("Move: %v", err)
			}
			// dst should exist
			rc, err := v.Open(ctx, "dst.txt")
			if err != nil {
				t.Fatalf("Open dst: %v", err)
			}
			got, _ := io.ReadAll(rc)
			rc.Close()
			if string(got) != "move me" {
				t.Errorf("dst content = %q, want \"move me\"", got)
			}
			// src should be gone
			_, err = v.Stat(ctx, "src.txt")
			if !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("expected ErrNotFound for src after Move, got %v", err)
			}
		})
	}
}

func TestMoveDir(t *testing.T) {
	for _, f := range factories {
		f := f
		t.Run(f.name, func(t *testing.T) {
			ctx := context.Background()
			v := f.make(t, "test-ns")
			if err := v.MkdirAll(ctx, "old/sub"); err != nil {
				t.Fatalf("MkdirAll: %v", err)
			}
			if err := v.Write(ctx, "old/sub/file.txt", strings.NewReader("x"), vfs.WriteOptions{}); err != nil {
				t.Fatalf("Write: %v", err)
			}
			if err := v.Move(ctx, "old", "new"); err != nil {
				t.Fatalf("Move dir: %v", err)
			}
			// File should now be under new/
			_, err := v.Stat(ctx, "new/sub/file.txt")
			if err != nil {
				t.Errorf("expected new/sub/file.txt to exist after dir move: %v", err)
			}
			// Old path should be gone
			_, err = v.Stat(ctx, "old")
			if !errors.Is(err, vfs.ErrNotFound) {
				t.Errorf("expected old dir to be gone after Move, got %v", err)
			}
		})
	}
}

func TestRegistryNamespaceConflict(t *testing.T) {
	reg := vfs.NewRegistry()
	ns := vfs.Namespace{ID: "ns1"}
	impl := vfs.NewMemVFS("ns1")
	if err := reg.Register(ns, impl); err != nil {
		t.Fatalf("first Register: %v", err)
	}
	err := reg.Register(ns, impl)
	if !errors.Is(err, vfs.ErrNamespaceConflict) {
		t.Errorf("expected ErrNamespaceConflict, got %v", err)
	}
}

// A write in flight and the trash are Quark's own entries; a user's dotfile is
// not, and hiding it would lose it from every listing-driven feature (#1828).
func TestLocalVFSListSkipsInternalEntriesButNotDotfiles(t *testing.T) {
	root := t.TempDir()
	for _, rel := range []string{".vfs-write-123", ".trash/gone.txt", ".env", "docs/.vfs-write-9", "docs/a.txt"} {
		full := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatalf("mkdir: %v", err)
		}
		if err := os.WriteFile(full, []byte("x"), 0o644); err != nil {
			t.Fatalf("write %s: %v", rel, err)
		}
	}
	v, err := vfs.NewLocalVFS(root, "test-ns")
	if err != nil {
		t.Fatalf("NewLocalVFS: %v", err)
	}

	infos, err := v.List(context.Background(), "", &vfs.ListFilter{Recursive: true})
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	var got []string
	for _, fi := range infos {
		got = append(got, fi.Path)
	}
	want := []string{".env", "docs", "docs/a.txt"}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("listed %v, want %v", got, want)
	}
}
