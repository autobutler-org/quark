package bookutil

import (
	"context"
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// memFS is an in-memory namespace holding paths.
func memFS(t *testing.T, paths ...string) vfs.VFS {
	t.Helper()
	mem := vfs.NewMemVFS("files")
	for _, p := range paths {
		if err := mem.Write(context.Background(), p, strings.NewReader("content"), vfs.WriteOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	return mem
}

// bookPaths is the sorted paths FindBooks returns for fsys.
func bookPaths(t *testing.T, fsys vfs.VFS) []string {
	t.Helper()
	result, err := FindBooks(context.Background(), FindBooksParams{FS: fsys})
	if err != nil {
		t.Fatalf("FindBooks: %v", err)
	}
	paths := make([]string, 0, len(result.Books))
	for _, book := range result.Books {
		paths = append(paths, book.Path)
	}
	slices.Sort(paths)
	return paths
}

func TestFindBooks(t *testing.T) {
	fsys := memFS(t,
		"book1.pdf", "book2.epub", "readme.txt",
		"subdir/book3.pdf", "subdir/image.jpg", "subdir/nested/book4.epub",
	)
	want := []string{"book1.pdf", "book2.epub", "subdir/book3.pdf", "subdir/nested/book4.epub"}
	if got := bookPaths(t, fsys); !slices.Equal(got, want) {
		t.Errorf("books = %v, want %v", got, want)
	}
}

// Books in the trash, the version store or a half-written upload are not books on the shelf.
func TestFindBooks_SkipsInternalNames(t *testing.T) {
	fsys := memFS(t, "kept.pdf", ".trash/old.pdf", storageutil.VersionsDirName+"/kept.pdf/1.pdf")
	if got := bookPaths(t, fsys); !slices.Equal(got, []string{"kept.pdf"}) {
		t.Errorf("books = %v, want [kept.pdf]", got)
	}
}

func TestFindBooks_Empty(t *testing.T) {
	result, err := FindBooks(context.Background(), FindBooksParams{FS: memFS(t)})
	if err != nil {
		t.Fatalf("FindBooks: %v", err)
	}
	if result.Books == nil || len(result.Books) != 0 {
		t.Errorf("books = %#v, want an empty, non-nil list", result.Books)
	}
}

// The size and modification time come through the namespace with each book.
func TestFindBooks_CarriesFileInfo(t *testing.T) {
	result, err := FindBooks(context.Background(), FindBooksParams{FS: memFS(t, "a/b.epub")})
	if err != nil {
		t.Fatalf("FindBooks: %v", err)
	}
	if len(result.Books) != 1 {
		t.Fatalf("books = %+v, want one", result.Books)
	}
	if book := result.Books[0]; book.Name != "b.epub" || book.Size != int64(len("content")) || book.ModTime.IsZero() {
		t.Errorf("book = %+v, want b.epub with its size and time", book)
	}
}

func TestFindBooks_MissingRoot(t *testing.T) {
	_, err := FindBooks(context.Background(), FindBooksParams{FS: missingFS{vfs.NewMemVFS("files")}})
	if !errors.Is(err, vfs.ErrNotFound) {
		t.Errorf("FindBooks = %v, want ErrNotFound", err)
	}
}

// missingFS is a namespace whose root is gone.
type missingFS struct{ vfs.VFS }

func (missingFS) List(context.Context, string, *vfs.ListFilter) ([]vfs.FileInfo, error) {
	return nil, vfs.ErrNotFound
}
