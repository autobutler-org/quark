// cspell:words prores apco

package videoutil

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/autobutler-org/sprocket/pkg/sprocket"
)

// The error-mapping contract of #3427 at this layer: every way a video can
// fail to open, probe, convert, trim, or thumbnail ends in an error a handler
// can tell apart from the others. An unsupported file is never missing, a
// corrupt one is never unsupported, and the sprocket sentinel that says why
// is always in the chain, and so in the message the logs get.
//
// fragmented.mp4 and prores-pcm.mov are copied from sprocket's corpus.
// audio-only.mp4 is one second of AAC and unsupported.avi half a second of
// MPEG-4 Part 2 in AVI, both made with ffmpeg's lavfi sources at the corpus's
// 128x72, 24 fps, and 440 Hz.
const (
	fragmentedFixture = "testdata/fragmented.mp4"
	proresFixture     = "testdata/prores-pcm.mov"
	audioOnlyFixture  = "testdata/audio-only.mp4"
	aviFixture        = "testdata/unsupported.avi"
)

// errorKinds is every error a handler maps to its own status or sentence.
// A failing row matches the ones it names and none of the rest.
var errorKinds = []error{
	vfs.ErrNotFound,
	vfs.ErrPermissionDenied,
	ErrNotAVideo,
	ErrCannotTrim,
	ErrCannotConvert,
	ErrNoDecoder,
	sprocket.ErrUnsupportedContainer,
	sprocket.ErrCorrupt,
	sprocket.ErrNoVideo,
	sprocket.ErrUnsupportedCodec,
}

// assertKinds fails unless err matches every error in want and no other
// error in errorKinds, and carries a reason beyond the sentinels it wraps.
func assertKinds(t *testing.T, err error, want ...error) {
	t.Helper()
	if err == nil {
		t.Fatalf("err = nil, want %v", want)
	}
	for _, kind := range errorKinds {
		if is, wanted := errors.Is(err, kind), slices.Contains(want, kind); is != wanted {
			t.Errorf("errors.Is(%q, %q) = %v, want %v", err, kind, is, wanted)
		}
	}
	reason := err.Error()
	for _, kind := range want {
		reason = strings.ReplaceAll(reason, kind.Error(), "")
	}
	if strings.Trim(reason, ": ") == "" {
		t.Errorf("err %q names its sentinels and no reason", err)
	}
}

// writeTemp writes data to a host file named name, for a row with no fixture.
func writeTemp(t *testing.T, name string, data []byte) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(p, data, 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

// truncatedClip is the first half of gopFixture: the moov is whole and the
// mdat declares more than is left, which sprocket reads as ErrCorrupt.
func truncatedClip(t *testing.T) string {
	t.Helper()
	clip, err := os.ReadFile(gopFixture)
	if err != nil {
		t.Fatal(err)
	}
	return writeTemp(t, "truncated.mp4", clip[:len(clip)/2])
}

func notAVideo(t *testing.T) string {
	t.Helper()
	return writeTemp(t, "not-video.mp4", []byte("not a video"))
}

func fixture(p string) func(*testing.T) string {
	return func(*testing.T) string { return p }
}

// unreadableFile is a vfs.File every read of fails with EIO, a disk or
// permission failure under a file that exists.
type unreadableFile struct{ vfs.File }

func (unreadableFile) Read([]byte) (int, error)          { return 0, syscall.EIO }
func (unreadableFile) ReadAt([]byte, int64) (int, error) { return 0, syscall.EIO }

// TestErrorMappingProbe is the metadata and formats column: what ProbeSource
// and Targets say for each kind of file.
func TestErrorMappingProbe(t *testing.T) {
	cases := []struct {
		name string
		file func(*testing.T) string
		// want is what ProbeSource and Targets fail with; nil means both
		// succeed.
		want []error
		// codec is the video codec a readable file probes as, named even
		// when nothing on the device can decode it.
		codec string
	}{
		{name: "an AVI, a container sprocket does not read", file: fixture(aviFixture),
			want: []error{ErrNotAVideo, sprocket.ErrUnsupportedContainer}},
		{name: "bytes that are not a video, named .mp4", file: notAVideo,
			want: []error{ErrNotAVideo, sprocket.ErrUnsupportedContainer}},
		{name: "a truncated MP4", file: truncatedClip,
			want: []error{ErrNotAVideo, sprocket.ErrCorrupt}},
		{name: "a ProRes MOV", file: fixture(proresFixture), codec: "apco"},
		{name: "an HEVC Matroska", file: fixture(hevcMKVFixture), codec: "hevc"},
		{name: "a fragmented MP4", file: fixture(fragmentedFixture), codec: "h264"},
		// An audio-only file is a readable file with no video track, not a
		// broken video: the empty codec is the signal, not an error.
		{name: "an audio-only MP4", file: fixture(audioOnlyFixture), codec: ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			src := openFixture(t, c.file(t))
			info, err := ProbeSource(context.Background(), src)
			_, targetsErr := Targets(src)
			if c.want != nil {
				assertKinds(t, err, c.want...)
				assertKinds(t, targetsErr, c.want...)
				return
			}
			if err != nil || targetsErr != nil {
				t.Fatalf("ProbeSource err = %v, Targets err = %v, want both nil", err, targetsErr)
			}
			if info.VideoCodec != c.codec {
				t.Errorf("VideoCodec = %q, want %q", info.VideoCodec, c.codec)
			}
		})
	}
}

// TestErrorMappingProbeKeepsAReadFailure is the permission/IO row: a file
// that exists but cannot be read is that read's error, never a file that is
// not a video.
func TestErrorMappingProbeKeepsAReadFailure(t *testing.T) {
	src := openFixture(t, gopFixture)
	src.File = unreadableFile{src.File}
	_, err := ProbeSource(context.Background(), src)
	if !errors.Is(err, syscall.EIO) {
		t.Fatalf("err = %v, want it to wrap EIO", err)
	}
	for _, kind := range errorKinds {
		if errors.Is(err, kind) {
			t.Errorf("err %q is %q, which relabels a read failure", err, kind)
		}
	}
	if _, err := Targets(src); !errors.Is(err, syscall.EIO) || errors.Is(err, ErrNotAVideo) {
		t.Errorf("Targets err = %v, want EIO and not ErrNotAVideo", err)
	}
}

// TestErrorMappingTargetsOfAProResMOV is the "no formats" row: a ProRes MOV
// is a readable video whose codecs fit no other container, so it has no
// targets and no error.
func TestErrorMappingTargetsOfAProResMOV(t *testing.T) {
	targets, err := Targets(openFixture(t, proresFixture))
	if err != nil || targets == nil || len(targets) != 0 {
		t.Fatalf("Targets = %#v, %v, want an empty list and no error", targets, err)
	}
}

// TestErrorMappingTargetsOfAFragmentedMP4 is the fragmented-convert row:
// Remux refuses every format for a fragmented MP4, naming why, so Targets
// offers none of them (#3419).
func TestErrorMappingTargetsOfAFragmentedMP4(t *testing.T) {
	for _, f := range Formats() {
		err := Remux(context.Background(), RemuxParams{Source: openFixture(t, fragmentedFixture), Output: io.Discard, Format: f})
		if !errors.Is(err, ErrCannotConvert) || !errors.Is(err, sprocket.ErrUnsupportedContainer) ||
			!strings.Contains(err.Error(), "fragmented") || !strings.Contains(err.Error(), f.Label()) {
			t.Errorf("Remux to %s = %v, want ErrCannotConvert naming %s and the fragmented source", f, err, f.Label())
		}
	}
	// sprocket.Info does not say a file is fragmented, so CanRemux alone
	// would offer the formats Remux then refuses. Targets asks Remux itself.
	if targets, err := Targets(openFixture(t, fragmentedFixture)); err != nil || len(targets) != 0 {
		t.Fatalf("Targets = %v, %v, want none", targets, err)
	}
}

// TestErrorMappingTrim is the trim column: each source Trim refuses says why,
// and the two it cannot cut say different things.
func TestErrorMappingTrim(t *testing.T) {
	cases := []struct {
		name string
		file func(*testing.T) string
		want []error
		// reason is what the message names, so the client can tell an
		// MPEG-TS source from a fragmented one.
		reason string
	}{
		{name: "an MPEG-TS source", file: fixture(tsFixture),
			want: []error{ErrCannotTrim, sprocket.ErrUnsupportedContainer}, reason: "MPEG-TS"},
		{name: "a fragmented MP4", file: fixture(fragmentedFixture),
			want: []error{ErrCannotTrim, sprocket.ErrUnsupportedContainer}, reason: "fragmented"},
		// A corrupt file is not one the device cannot cut: it is damaged.
		{name: "a truncated MP4", file: truncatedClip,
			want: []error{sprocket.ErrCorrupt}, reason: "mdat"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Trim(context.Background(), TrimParams{Source: openFixture(t, c.file(t)), Output: io.Discard, End: time.Second})
			assertKinds(t, err, c.want...)
			if !strings.Contains(err.Error(), c.reason) {
				t.Errorf("err %q does not name %q", err, c.reason)
			}
		})
	}
}

// TestErrorMappingTrimFileLeavesNothingBehind is every refused trim through
// the VFS: the error is the row's, and no clip, whole or partial, is left.
func TestErrorMappingTrimFileLeavesNothingBehind(t *testing.T) {
	cases := []struct {
		name, src string
		file      func(*testing.T) string
		want      []error
	}{
		{name: "an AVI", src: "clip.avi", file: fixture(aviFixture),
			want: []error{ErrNotAVideo, sprocket.ErrUnsupportedContainer}},
		{name: "bytes that are not a video", src: "clip.mp4", file: notAVideo,
			want: []error{ErrNotAVideo, sprocket.ErrUnsupportedContainer}},
		{name: "a truncated MP4", src: "clip.mp4", file: truncatedClip,
			want: []error{ErrNotAVideo, sprocket.ErrCorrupt}},
		{name: "a fragmented MP4", src: "clip.mp4", file: fixture(fragmentedFixture),
			want: []error{ErrCannotTrim, sprocket.ErrUnsupportedContainer}},
		{name: "an MPEG-TS source", src: "clip.ts", file: fixture(tsFixture),
			want: []error{ErrCannotTrim, sprocket.ErrUnsupportedContainer}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			fsys := memWith(t, c.file(t), c.src)
			_, err := TrimFile(context.Background(), TrimFileParams{FS: fsys, Path: c.src, End: time.Second})
			assertKinds(t, err, c.want...)
			if got := names(t, fsys, ""); !slices.Equal(got, []string{c.src}) {
				t.Errorf("namespace holds %v, want only the source", got)
			}
		})
	}
}

// TestErrorMappingKeyframe is the thumbnail column: a codec the device cannot
// decode is ErrNoDecoder, the client-render fallback, and a file with no
// video, a damaged one, or one that is not a video each say so instead.
func TestErrorMappingKeyframe(t *testing.T) {
	cases := []struct {
		name string
		file func(*testing.T) string
		want []error
	}{
		{name: "an HEVC Matroska", file: fixture(hevcMKVFixture),
			want: []error{ErrNoDecoder, sprocket.ErrUnsupportedCodec}},
		{name: "a ProRes MOV", file: fixture(proresFixture),
			want: []error{ErrNoDecoder, sprocket.ErrUnsupportedCodec}},
		{name: "an audio-only MP4", file: fixture(audioOnlyFixture),
			want: []error{sprocket.ErrNoVideo}},
		{name: "a truncated MP4", file: truncatedClip,
			want: []error{sprocket.ErrCorrupt}},
		{name: "an AVI", file: fixture(aviFixture),
			want: []error{sprocket.ErrUnsupportedContainer}},
		{name: "bytes that are not a video", file: notAVideo,
			want: []error{sprocket.ErrUnsupportedContainer}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Keyframe(KeyframeParams{Source: c.file(t)})
			assertKinds(t, err, c.want...)
		})
	}
}

// TestErrorMappingOpenSource is the missing-file row, the regression guard:
// a path with nothing at it is vfs.ErrNotFound, and never a file that is not
// a video, which is what the handlers tell apart.
func TestErrorMappingOpenSource(t *testing.T) {
	fsys := memWith(t, aviFixture, "clip.avi")
	_, err := OpenSource(context.Background(), OpenSourceParams{FS: fsys, Path: "gone.mp4"})
	if !errors.Is(err, vfs.ErrNotFound) {
		t.Fatalf("err = %v, want vfs.ErrNotFound", err)
	}
	for _, kind := range errorKinds {
		if kind != vfs.ErrNotFound && errors.Is(err, kind) {
			t.Errorf("err %q of a missing file is also %q", err, kind)
		}
	}
	// The AVI beside it opens: it exists, so whatever fails later is not
	// "missing".
	src, err := OpenSource(context.Background(), OpenSourceParams{FS: fsys, Path: "clip.avi"})
	if err != nil {
		t.Fatalf("OpenSource of an existing AVI = %v", err)
	}
	_ = src.Close()
}
