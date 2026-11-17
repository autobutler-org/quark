package pptxutil_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/pptxutil"
)

func TestMediaDirsOf(t *testing.T) {
	tests := []struct {
		name string
		path string
		want []string
	}{
		{"root", "Talk.qslide", []string{"Talk_media"}},
		{"nested", "work/Talk.qslide", []string{"work/Talk_media"}},
		{"numbered", "work/Talk_(1).qslide", []string{"work/Talk_(1)_media", "work/Talk_media"}},
		{"extension case", "Talk.QSLIDE", []string{"Talk_media"}},
		{"not numbered", "Talk_(x).qslide", []string{"Talk_(x)_media"}},
		{"only a number", "_(1).qslide", []string{"_(1)_media"}},
		{"not a presentation", "Talk.pptx", nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := pptxutil.MediaDirsOf(tt.path); !slices.Equal(got, tt.want) {
				t.Fatalf("MediaDirsOf(%q) = %v, want %v", tt.path, got, tt.want)
			}
		})
	}
}

func TestImageSources(t *testing.T) {
	deck := `{"schemaVersion":1,"title":"Talk","slides":[
		{"background":{"image":"background.png"},"elements":[
			{"type":"image","source":"photo.png"},
			{"type":"group","children":[{"type":"image","source":"nested.png"}]},
			{"type":"image","source":"photo.png"}
		]}
	]}`
	title, got, err := pptxutil.ImageSources(strings.NewReader(deck))
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"background.png", "photo.png", "nested.png"}
	if title != "Talk" || !slices.Equal(got, want) {
		t.Fatalf("title and image sources = %q, %v; want Talk, %v", title, got, want)
	}
}

func TestMediaDir(t *testing.T) {
	if got := pptxutil.MediaDir("", "Talk"); got != "Talk_media" {
		t.Fatalf("MediaDir = %q, want Talk_media", got)
	}
}
