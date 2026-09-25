package videoutil

import (
	"context"
	"errors"
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
// display matrix, and h264-aac.ts is an MPEG-TS copy of the same streams.
const (
	gopFixture    = "testdata/h264-gop12.mp4"
	rotateFixture = "testdata/rotate-90.mp4"
	tsFixture     = "testdata/h264-aac.ts"
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

func TestTrimSnapsToTheKeyframeBefore(t *testing.T) {
	out := filepath.Join(t.TempDir(), "clip.mp4")
	result, err := Trim(context.Background(), TrimParams{Source: gopFixture, Output: out, Start: 1200 * time.Millisecond, End: 2200 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	if result.Start != time.Second {
		t.Fatalf("Start = %v, want the keyframe at 1s", result.Start)
	}
	info, err := Probe(context.Background(), out)
	if err != nil {
		t.Fatalf("the clip does not probe: %v", err)
	}
	if info.Duration < time.Second || info.Duration > 1300*time.Millisecond || info.VideoCodec != "h264" {
		t.Fatalf("clip = %+v, want about 1.2s of h264", *info)
	}
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

func TestFormatTimestamp(t *testing.T) {
	cases := []struct {
		d    time.Duration
		want string
	}{
		{0, "00:00:00.000"},
		{time.Second, "00:00:01.000"},
		{90*time.Second + 500*time.Millisecond, "00:01:30.500"},
		{3661*time.Second + 123*time.Millisecond, "01:01:01.123"},
	}
	for _, c := range cases {
		if got := formatTimestamp(c.d); got != c.want {
			t.Errorf("formatTimestamp(%v) = %q, want %q", c.d, got, c.want)
		}
	}
}
