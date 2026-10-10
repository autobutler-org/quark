package storageutil

import (
	"slices"
	"testing"
)

func TestArchiveExt(t *testing.T) {
	cases := []struct {
		path string
		want string
	}{
		{"archive.zip", ".zip"},
		{"archive.tar.gz", ".tar.gz"},
		{"ARCHIVE.TAR.GZ", ".tar.gz"},
		{"archive.tgz", ".tgz"},
		{"archive.tar.bz2", ".tar.bz2"},
		{"archive.rar", ".rar"},
		{"archive.7z", ".7z"},
		{"archive.tar", ".tar"},
		{"archive.gz", ".gz"},
		{"file.txt", ".txt"},
	}
	for _, c := range cases {
		got := archiveExt(c.path)
		if got != c.want {
			t.Errorf("archiveExt(%q) = %q; want %q", c.path, got, c.want)
		}
	}
}

func TestArchiveStem_StripsDoubleExtensions(t *testing.T) {
	cases := map[string]string{
		"foo.tar.gz":     "foo",
		"FOO.TAR.GZ":     "FOO",
		"foo.tgz":        "foo",
		"foo.zip":        "foo",
		"a/b/foo.tar":    "foo",
		"foo.rar":        "foo",
		"foo.7z":         "foo",
		"notes.txt.gz":   "notes.txt",
		"foo.bar.zip":    "foo.bar",
		"no-extension":   "no-extension",
		"dir/photos.ZIP": "photos",
	}
	for name, want := range cases {
		if got := ArchiveStem(name); got != want {
			t.Errorf("ArchiveStem(%q) = %q; want %q", name, got, want)
		}
	}
}

func TestIsSupportedArchive(t *testing.T) {
	for _, name := range []string{"a.zip", "a.TAR.GZ", "a.tgz", "a.gz", "a.rar", "a.7z", "a.tar"} {
		if !IsSupportedArchive(name) {
			t.Errorf("IsSupportedArchive(%q) = false, want true", name)
		}
	}
	for _, name := range []string{"a.txt", "a.tar.bz2", "zip"} {
		if IsSupportedArchive(name) {
			t.Errorf("IsSupportedArchive(%q) = true, want false", name)
		}
	}
}

func TestSupportedArchiveExts_ContainsExpected(t *testing.T) {
	supported := SupportedArchiveExts()
	for _, ext := range []string{".7z", ".gz", ".rar", ".tar", ".tar.gz", ".tgz", ".zip"} {
		if !slices.Contains(supported, ext) {
			t.Errorf("SupportedArchiveExts() missing %q", ext)
		}
	}
}
