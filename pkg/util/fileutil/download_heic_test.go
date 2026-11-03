package fileutil_test

import (
	"context"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// The device has no HEIC decoder (#2382): a ?format=jpeg download of a HEIC
// or HEIF serves the stored bytes, while any other image is still converted.
func TestOpenVFSDownload_ServesHEICAsStored(t *testing.T) {
	ctx := context.Background()
	fsys := vfs.NewMemVFS("files")
	cases := map[string]struct {
		contentType string
		want        fileutil.DownloadKind
	}{
		"IMG_1.HEIC": {"image/heic", fileutil.DownloadContents},
		"IMG_2.heif": {"image/heif", fileutil.DownloadContents},
		"scan.tiff":  {"image/tiff", fileutil.DownloadJPEG},
	}
	for name, tc := range cases {
		if err := fsys.Write(ctx, name, strings.NewReader("x"), vfs.WriteOptions{ContentType: tc.contentType}); err != nil {
			t.Fatal(err)
		}
		got, err := fileutil.OpenVFSDownload(fileutil.OpenVFSDownloadParams{Ctx: ctx, FS: fsys, FilePath: name, WantsJPEG: true})
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if got.Kind != tc.want {
			t.Errorf("%s: kind = %s, want %s", name, got.Kind, tc.want)
		}
		if tc.want == fileutil.DownloadContents && (got.FileName != name || got.ContentType != tc.contentType) {
			t.Errorf("%s: served as %s (%s), want it as stored", name, got.FileName, got.ContentType)
		}
	}
}
