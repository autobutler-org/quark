package thumbnailutil_test

import (
	"testing"

	"github.com/autobutler-org/quark/pkg/util/iosemutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"
)

func TestSemaphoreClass(t *testing.T) {
	cases := []struct {
		path    string
		isVideo bool
		want    iosemutil.Class
	}{
		{"photos/a.jpg", false, iosemutil.Decode},
		{"photos/a.heic", false, iosemutil.Decode},
		{"photos/a.CR2", false, iosemutil.Raw},
		{"photos/a.mp4", true, iosemutil.Video},
	}
	for _, tc := range cases {
		if got := thumbnailutil.SemaphoreClass(tc.path, tc.isVideo); got != tc.want {
			t.Errorf("SemaphoreClass(%q, %v) = %v, want %v", tc.path, tc.isVideo, got, tc.want)
		}
	}
}
