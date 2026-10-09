package videoutil

import (
	"bytes"
	"context"
	"errors"
	"image"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

// The fixtures in testdata are copied from sprocket's own test corpus
// (github.com/autobutler-org/sprocket, testdata/corpus): tiny synthetic clips,
// 128x72 at 24 fps with a 440 Hz tone. h264-gop12.mp4 is three seconds with a
// keyframe every half second, rotate-90.mp4 carries a 90 degree clockwise
// display matrix, h264-aac.ts is an MPEG-TS copy of the same streams, and
// hevc-aac-copy.mkv is two seconds of HEVC and AAC that ffmpeg copied into
// Matroska, with a keyframe only at zero. av1-opus.webm and vp8-vorbis.webm
// are two seconds each of the codecs Keyframe has a decoder for.
const (
	gopFixture     = "testdata/h264-gop12.mp4"
	rotateFixture  = "testdata/rotate-90.mp4"
	tsFixture      = "testdata/h264-aac.ts"
	hevcMKVFixture = "testdata/hevc-aac-copy.mkv"
	av1Fixture     = "testdata/av1-opus.webm"
	vp8Fixture     = "testdata/vp8-vorbis.webm"
)

func TestProbe(t *testing.T) {
	info, err := Probe(context.Background(), gopFixture)
	if err != nil {
		t.Fatal(err)
	}
	want := VideoInfo{Duration: 3 * time.Second, Width: 128, Height: 72, VideoCodec: "h264", AudioCodec: "aac", Framerate: 24}
	if info.Duration != want.Duration || info.Width != want.Width || info.Height != want.Height ||
		info.VideoCodec != want.VideoCodec || info.AudioCodec != want.AudioCodec || info.Framerate != want.Framerate ||
		info.Rotation != 0 || info.Bitrate <= 0 {
		t.Fatalf("Probe = %+v, want %+v with a positive bitrate", *info, want)
	}
}

// TestProbeRotationMatchesFFprobe pins the sign: ffprobe reports this file's
// display matrix as rotation -90, which the old ffprobe-based Probe
// normalized to 270, and sprocket reports it as 90 clockwise.
func TestProbeRotationMatchesFFprobe(t *testing.T) {
	info, err := Probe(context.Background(), rotateFixture)
	if err != nil {
		t.Fatal(err)
	}
	if info.Rotation != 270 {
		t.Fatalf("Rotation = %d, want 270", info.Rotation)
	}
}

func TestProbeRejectsANonVideo(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notes.mp4")
	if err := os.WriteFile(path, []byte("not a video"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Probe(context.Background(), path); err == nil {
		t.Fatal("Probe of a text file succeeded")
	}
}

func TestCounterclockwise(t *testing.T) {
	for clockwise, want := range map[int]int{0: 0, 90: 270, 180: 180, 270: 90} {
		if got := counterclockwise(clockwise); got != want {
			t.Errorf("counterclockwise(%d) = %d, want %d", clockwise, got, want)
		}
	}
}

func TestFFprobeCodecName(t *testing.T) {
	for name, want := range map[string]string{
		"ac-3": "ac3", "ec-3": "eac3", "fLaC": "flac", "samr": "amr_nb", "sawb": "amr_wb",
		"h264": "h264", "aac": "aac", "alac": "alac", "": "",
	} {
		if got := ffprobeCodecName(name); got != want {
			t.Errorf("ffprobeCodecName(%q) = %q, want %q", name, got, want)
		}
	}
}

func TestFormats(t *testing.T) {
	want := []Format{"mp4", "mov", "mkv", "webm", "m4v", "3gp", "3g2", "ts"}
	if got := Formats(); !slices.Equal(got, want) {
		t.Fatalf("Formats() = %v, want %v", got, want)
	}
	for _, f := range want {
		if !f.Valid() || f.Label() == "" {
			t.Errorf("%s: Valid() = %v, Label() = %q", f, f.Valid(), f.Label())
		}
	}
	for _, f := range []Format{"avi", "wmv", ""} {
		if f.Valid() || f.Label() != "" {
			t.Errorf("%q is not a format sprocket writes, but Valid() = %v, Label() = %q", f, f.Valid(), f.Label())
		}
	}
}

func TestTargets(t *testing.T) {
	cases := []struct {
		name   string
		source string
		want   []Format
	}{
		// H.264 and AAC fit everything but WebM, and the source's own format
		// is left out.
		{"mp4", gopFixture, []Format{"mov", "mkv", "m4v", "3gp", "3g2", "ts"}},
		// sprocket writes no Matroska from a transport stream.
		{"ts", tsFixture, []Format{"mp4", "mov", "m4v", "3gp", "3g2"}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, err := Targets(c.source)
			if err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(got, c.want) {
				t.Fatalf("Targets = %v, want %v", got, c.want)
			}
		})
	}
}

func TestTrimFormat(t *testing.T) {
	for path, want := range map[string]Format{"a.mp4": "mp4", "b.MKV": "mkv", "c.mov": "mov", "d.avi": "mp4", "e": "mp4", "f.ts": "ts"} {
		if got := TrimFormat(path); got != want {
			t.Errorf("TrimFormat(%q) = %q, want %q", path, got, want)
		}
	}
}

// TestTrimStartsWhereAsked cuts between keyframes: the clip is shown from the
// requested start, with the frames back to the keyframe at 1s hidden, so it
// lasts the second that was asked for rather than 1.2s.
func TestTrimStartsWhereAsked(t *testing.T) {
	cases := []struct {
		name, source, format, codec string
		start, end                  time.Duration
	}{
		{"mp4", gopFixture, "mp4", "h264", 1200 * time.Millisecond, 2200 * time.Millisecond},
		// sprocket v0.2.0 could not read ffmpeg's HEVC Matroska at all.
		{"hevc mkv", hevcMKVFixture, "mkv", "hevc", 500 * time.Millisecond, 1500 * time.Millisecond},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := filepath.Join(t.TempDir(), "clip."+c.format)
			result, err := Trim(context.Background(), TrimParams{Source: c.source, Output: out, Start: c.start, End: c.end})
			if err != nil {
				t.Fatal(err)
			}
			if result.Start != c.start {
				t.Fatalf("Start = %v, want the requested %v", result.Start, c.start)
			}
			info, err := Probe(context.Background(), out)
			if err != nil {
				t.Fatalf("the clip does not probe: %v", err)
			}
			if info.Duration < 900*time.Millisecond || info.Duration > 1100*time.Millisecond || info.VideoCodec != c.codec {
				t.Fatalf("clip = %+v, want about 1s of %s", *info, c.codec)
			}
		})
	}
}

// TestTrimKeepsTheMiddle checks the clip's content, not just its length. A
// trim copies samples without re-encoding them, so the payload the clip opens
// with is a run of the source's bytes, and it has to come from the keyframe
// before the start, whose hidden lead-in the clip carries, rather than from
// the start of the source.
func TestTrimKeepsTheMiddle(t *testing.T) {
	out := filepath.Join(t.TempDir(), "clip.mp4")
	if _, err := Trim(context.Background(), TrimParams{Source: gopFixture, Output: out, Start: 1200 * time.Millisecond, End: 2200 * time.Millisecond}); err != nil {
		t.Fatal(err)
	}
	source, clip := mdatPayload(t, gopFixture), mdatPayload(t, out)
	at := bytes.Index(source, clip[:256])
	if at <= 0 {
		t.Fatalf("the clip's payload opens at byte %d of the source's, want past its start", at)
	}
}

// TestTrimACutAgain trims a clip Trim wrote, in every container it keeps a
// source in: a second cut is measured from where the first one is shown, and
// has to find the keyframes it wrote, lead-in and all, to show from where it
// was asked.
func TestTrimACutAgain(t *testing.T) {
	for _, format := range []Format{"mp4", "mov", "mkv"} {
		dir := t.TempDir()
		source := filepath.Join(dir, "source."+string(format))
		if err := Remux(context.Background(), RemuxParams{Source: gopFixture, Output: source, Format: format}); err != nil {
			t.Fatalf("%s: %v", format, err)
		}
		clip := filepath.Join(dir, "clip."+string(format))
		if _, err := Trim(context.Background(), TrimParams{Source: source, Output: clip, Start: 1200 * time.Millisecond, End: 2900 * time.Millisecond}); err != nil {
			t.Fatalf("%s: %v", format, err)
		}
		again := filepath.Join(dir, "again."+string(format))
		result, err := Trim(context.Background(), TrimParams{Source: clip, Output: again, Start: 600 * time.Millisecond, End: 1500 * time.Millisecond})
		if err != nil {
			t.Fatalf("%s: %v", format, err)
		}
		if result.Start != 600*time.Millisecond {
			t.Errorf("%s: Start = %v, want the requested 0.6s", format, result.Start)
		}
	}
}

// mdatPayload returns what follows the mdat box header in the MP4 at path,
// skipping the 64-bit size a header carries when its 32-bit size is 1.
func mdatPayload(t *testing.T, path string) []byte {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	at := bytes.Index(data, []byte("mdat"))
	if at < 4 {
		t.Fatalf("%s has no mdat box", path)
	}
	if bytes.Equal(data[at-4:at], []byte{0, 0, 0, 1}) {
		return data[at+12:]
	}
	return data[at+4:]
}

func TestTrimRefusesATransportStream(t *testing.T) {
	out := filepath.Join(t.TempDir(), "clip.ts")
	_, err := Trim(context.Background(), TrimParams{Source: tsFixture, Output: out, Start: 0, End: time.Second})
	if !errors.Is(err, ErrCannotTrim) {
		t.Fatalf("err = %v, want ErrCannotTrim", err)
	}
	if _, statErr := os.Stat(out); !os.IsNotExist(statErr) {
		t.Fatalf("a failed trim left its output behind: %v", statErr)
	}
}

func TestRemux(t *testing.T) {
	out := filepath.Join(t.TempDir(), "out")
	var progress []float64
	err := Remux(context.Background(), RemuxParams{Source: gopFixture, Output: out, Format: "mkv", OnProgress: func(f float64) {
		progress = append(progress, f)
	}})
	if err != nil {
		t.Fatal(err)
	}
	info, err := Probe(context.Background(), out)
	if err != nil {
		t.Fatalf("the output does not probe: %v", err)
	}
	if info.VideoCodec != "h264" || info.AudioCodec != "aac" || info.Width != 128 || info.Height != 72 {
		t.Fatalf("output = %+v, want the source's streams", *info)
	}
	if len(progress) == 0 || !slices.IsSorted(progress) || progress[len(progress)-1] > 1 {
		t.Fatalf("progress = %v, want rising fractions no higher than 1", progress)
	}
}

func TestRemuxFailuresLeaveNothingBehind(t *testing.T) {
	canceled, cancel := context.WithCancel(context.Background())
	cancel()
	cases := []struct {
		name   string
		ctx    context.Context
		format Format
		want   error
	}{
		{"codecs WebM cannot hold", context.Background(), "webm", nil},
		{"canceled", canceled, "mkv", context.Canceled},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := filepath.Join(t.TempDir(), "out")
			err := Remux(c.ctx, RemuxParams{Source: gopFixture, Output: out, Format: c.format})
			if err == nil || (c.want != nil && !errors.Is(err, c.want)) {
				t.Fatalf("err = %v, want %v", err, c.want)
			}
			if _, statErr := os.Stat(out); !os.IsNotExist(statErr) {
				t.Fatalf("a failed remux left its output behind: %v", statErr)
			}
		})
	}
}

func TestRemuxRefusesAnUnknownFormat(t *testing.T) {
	if err := Remux(context.Background(), RemuxParams{Source: gopFixture, Output: filepath.Join(t.TempDir(), "out"), Format: "avi"}); err == nil {
		t.Fatal("Remux into avi succeeded")
	}
}

func TestKeyframeDecodesAV1AndVP8(t *testing.T) {
	// Nothing on PATH: the frame comes out of the Go decoder, not ffmpeg.
	t.Setenv("PATH", t.TempDir())
	for _, fixture := range []string{av1Fixture, vp8Fixture} {
		result, err := Keyframe(KeyframeParams{Source: fixture, At: time.Second})
		if err != nil {
			t.Errorf("Keyframe(%s): %v", fixture, err)
			continue
		}
		if size := result.Image.Bounds().Size(); size != image.Pt(128, 72) {
			t.Errorf("Keyframe(%s) is %v, want the clip's 128x72", fixture, size)
		}
	}
}

func TestKeyframeReportsACodecWithNoDecoder(t *testing.T) {
	for _, fixture := range []string{gopFixture, tsFixture, hevcMKVFixture} {
		if _, err := Keyframe(KeyframeParams{Source: fixture}); !errors.Is(err, ErrNoDecoder) {
			t.Errorf("Keyframe(%s) = %v, want ErrNoDecoder", fixture, err)
		}
	}
}

func TestKeyframeRejectsANonVideo(t *testing.T) {
	path := filepath.Join(t.TempDir(), "notes.mp4")
	if err := os.WriteFile(path, []byte("not a video"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := Keyframe(KeyframeParams{Source: path}); err == nil || errors.Is(err, ErrNoDecoder) {
		t.Errorf("Keyframe on a text file = %v, want an error that is not ErrNoDecoder", err)
	}
}
