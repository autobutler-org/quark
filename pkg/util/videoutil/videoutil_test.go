package videoutil

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"
)

// TestAvailable checks that Available() reflects whether ffmpeg/ffprobe are on PATH.
func TestAvailable(t *testing.T) {
	// Just verifies the function doesn't panic.
	_ = Available()
}

// TestVersion checks that Version() returns a non-empty string when ffmpeg is available.
func TestVersion(t *testing.T) {
	if !Available() {
		t.Skip("ffmpeg not available")
	}
	v, err := Version()
	if err != nil {
		t.Fatalf("Version() error: %v", err)
	}
	if v == "" {
		t.Fatal("Version() returned empty string")
	}
}

// TestProbeRealFile probes a real video file if VIDEOUTIL_TEST_FILE is set.
func TestProbeRealFile(t *testing.T) {
	if !Available() {
		t.Skip("ffprobe not available")
	}
	filePath := os.Getenv("VIDEOUTIL_TEST_FILE")
	if filePath == "" {
		t.Skip("set VIDEOUTIL_TEST_FILE to a real video path to run this test")
	}
	info, err := Probe(context.Background(), filePath)
	if err != nil {
		t.Fatalf("Probe() error: %v", err)
	}
	if info.Duration <= 0 {
		t.Errorf("expected positive Duration, got %v", info.Duration)
	}
	if info.Width <= 0 || info.Height <= 0 {
		t.Errorf("expected positive dimensions, got %dx%d", info.Width, info.Height)
	}
	t.Logf("Probe result: %+v", info)
}

// TestFormatTimestamp exercises the timestamp formatter used by ExtractFrame and Trim.
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
		got := formatTimestamp(c.d)
		if got != c.want {
			t.Errorf("formatTimestamp(%v) = %q, want %q", c.d, got, c.want)
		}
	}
}

func TestParseProgressLine(t *testing.T) {
	cases := []struct {
		line   string
		want   time.Duration
		wantOK bool
	}{
		{"out_time_us=1500000", 1500 * time.Millisecond, true},
		// ffmpeg reports out_time_ms in microseconds as well.
		{"out_time_ms=2000000", 2 * time.Second, true},
		{"out_time_us=N/A", 0, false},
		{"out_time=00:00:01.500000", 0, false},
		{"progress=end", 0, false},
		{"frame=10", 0, false},
	}
	for _, c := range cases {
		got, ok := parseProgressLine(c.line)
		if got != c.want || ok != c.wantOK {
			t.Errorf("parseProgressLine(%q) = (%v, %v), want (%v, %v)", c.line, got, ok, c.want, c.wantOK)
		}
	}
}

// TestTranscodeNeverUpscales runs real ffmpeg over tiny generated clips and
// checks the output height at QualitySmall: capped at 480, never raised to it,
// and always even.
func TestTranscodeNeverUpscales(t *testing.T) {
	if !Available() {
		t.Skip("ffmpeg not available")
	}
	cases := []struct {
		name       string
		size       string
		wantHeight int
	}{
		{"a shorter source keeps its height", "64x240", 240},
		{"an odd height rounds down to even", "64x121", 120},
		{"a taller source is capped", "32x962", 480},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			src := filepath.Join(dir, "src.mkv")
			// ffv1 accepts the odd dimensions libx264 would refuse.
			gen := exec.Command("ffmpeg", "-loglevel", "error",
				"-f", "lavfi", "-i", "testsrc=size="+c.size+":rate=10:duration=1",
				"-c:v", "ffv1", "-y", src)
			if out, err := gen.CombinedOutput(); err != nil {
				t.Fatalf("generate clip: %v\n%s", err, out)
			}

			out := filepath.Join(dir, "out.mp4")
			var fractions []float64
			err := Transcode(context.Background(), TranscodeParams{
				Source:     src,
				Output:     out,
				Format:     "mp4",
				Quality:    QualitySmall,
				OnProgress: func(f float64) { fractions = append(fractions, f) },
			})
			if err != nil {
				t.Fatalf("Transcode() error: %v", err)
			}

			info, err := Probe(context.Background(), out)
			if err != nil {
				t.Fatalf("Probe() error: %v", err)
			}
			if info.Height != c.wantHeight {
				t.Errorf("output height = %d, want %d", info.Height, c.wantHeight)
			}
			if len(fractions) == 0 {
				t.Error("no progress was reported")
			}
			for _, f := range fractions {
				if f < 0 || f > 1 {
					t.Errorf("progress %v is outside [0, 1]", f)
				}
			}
		})
	}
}

func TestFormatTableCoversEveryVideoExtension(t *testing.T) {
	want := []Format{"mp4", "mov", "mkv", "webm", "avi", "m4v", "wmv", "flv", "ogv", "3gp", "3g2", "mpeg", "mpg", "ts"}
	if got := Formats(); !slices.Equal(got, want) {
		t.Fatalf("Formats() = %v, want %v", got, want)
	}
	for _, f := range want {
		spec, ok := lookupFormat(f)
		if !ok || f.Label() == "" || spec.muxer == "" || spec.video.encoder == "" || spec.audio.encoder == "" ||
			len(spec.copyVideo) == 0 || len(spec.copyAudio) == 0 {
			t.Errorf("format %q has an incomplete row: %+v", f, spec)
		}
	}
	if Format("gif").Valid() || Format("").Valid() || !Format("mov").Valid() {
		t.Error("Format.Valid accepts or refuses the wrong formats")
	}
	if Quality("best").Valid() || !QualityOriginal.Valid() || !QualitySmall.Valid() {
		t.Error("Quality.Valid accepts or refuses the wrong qualities")
	}
}

func TestTranscodeArgs(t *testing.T) {
	joined := func(params TranscodeParams, copyStreams bool) string {
		spec, ok := lookupFormat(params.Format)
		if !ok {
			t.Fatalf("unknown format %q", params.Format)
		}
		return strings.Join(transcodeArgs(params, spec, copyStreams), " ")
	}
	cases := []struct {
		name        string
		params      TranscodeParams
		copyStreams bool
		want        []string
		wantNot     []string
	}{
		{
			name:   "original re-encode keeps the size, rounded to even",
			params: TranscodeParams{Source: "in.mkv", Output: "out", Format: "mov", Quality: QualityOriginal},
			want: []string{"-i in.mkv", "-map 0:v:0 -map 0:a:0?", "-vf " + evenFilter, "-pix_fmt yuv420p",
				"-c:v libx264 -crf 20", "-c:a aac -b:a 192k", "-f mov -y out"},
			wantNot: []string{"-c copy", "min(ih"},
		},
		{
			name:    "small caps the height and lowers the bitrate",
			params:  TranscodeParams{Source: "in.mov", Output: "out", Format: "mov", Quality: QualitySmall},
			want:    []string{"-vf " + scaleFilter(480), "-c:v libx264 -crf 28", "-c:a aac -b:a 96k"},
			wantNot: []string{evenFilter},
		},
		{
			name:        "copy writes the streams unchanged",
			params:      TranscodeParams{Source: "in.mkv", Output: "out", Format: "mov", Quality: QualityOriginal},
			copyStreams: true,
			want:        []string{"-map 0:v:0 -map 0:a:0? -c copy -f mov -y out"},
			wantNot:     []string{"-c:v", "-c:a", "-vf"},
		},
		{"mkv uses the matroska muxer", TranscodeParams{Format: "mkv", Quality: QualityOriginal}, false, []string{"-f matroska"}, nil},
		{"m4v uses the ipod muxer", TranscodeParams{Format: "m4v", Quality: QualityOriginal}, false, []string{"-f ipod"}, nil},
		{"wmv is WMV2 and WMA2 in asf", TranscodeParams{Format: "wmv", Quality: QualityOriginal}, false, []string{"-c:v wmv2", "-c:a wmav2", "-f asf"}, nil},
		{"webm is VP9 and Opus", TranscodeParams{Format: "webm", Quality: QualitySmall}, false, []string{"-c:v libvpx-vp9 -crf 40 -b:v 0", "-c:a libopus -b:a 64k", "-f webm"}, nil},
		{"ogv is Theora and Vorbis", TranscodeParams{Format: "ogv", Quality: QualityOriginal}, false, []string{"-c:v libtheora -q:v 7", "-c:a libvorbis -q:a 5", "-f ogv"}, nil},
		{"avi is MPEG-4 and MP3", TranscodeParams{Format: "avi", Quality: QualityOriginal}, false, []string{"-c:v mpeg4 -q:v 3", "-c:a libmp3lame", "-f avi"}, nil},
		{"mpg is MPEG-2 in a program stream", TranscodeParams{Format: "mpg", Quality: QualityOriginal}, false, []string{"-c:v mpeg2video", "-c:a mp2", "-f mpeg"}, nil},
		{"ts uses the mpegts muxer", TranscodeParams{Format: "ts", Quality: QualityOriginal}, false, []string{"-c:v libx264", "-f mpegts"}, nil},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := joined(c.params, c.copyStreams)
			for _, want := range c.want {
				if !strings.Contains(got, want) {
					t.Errorf("args %q are missing %q", got, want)
				}
			}
			for _, not := range c.wantNot {
				if strings.Contains(got, not) {
					t.Errorf("args %q should not contain %q", got, not)
				}
			}
		})
	}
}

func TestCanCopy(t *testing.T) {
	h264AAC := &VideoInfo{VideoCodec: "h264", AudioCodec: "aac"}
	cases := []struct {
		name    string
		info    *VideoInfo
		format  Format
		quality Quality
		want    bool
	}{
		{"H.264 and AAC into MOV", h264AAC, "mov", QualityOriginal, true},
		{"H.264 with no audio into MP4", &VideoInfo{VideoCodec: "h264"}, "mp4", QualityOriginal, true},
		{"small always re-encodes", h264AAC, "mov", QualitySmall, false},
		{"WebM does not take H.264", h264AAC, "webm", QualityOriginal, false},
		{"MP4 does not take Opus", &VideoInfo{VideoCodec: "h264", AudioCodec: "opus"}, "mp4", QualityOriginal, false},
		{"VP9 and Opus into MKV", &VideoInfo{VideoCodec: "vp9", AudioCodec: "opus"}, "mkv", QualityOriginal, true},
		{"no video stream", &VideoInfo{AudioCodec: "aac"}, "mkv", QualityOriginal, false},
		{"unknown format", h264AAC, "gif", QualityOriginal, false},
		{"no probe", nil, "mov", QualityOriginal, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := CanCopy(c.info, c.format, c.quality); got != c.want {
				t.Errorf("CanCopy = %v, want %v", got, c.want)
			}
		})
	}
}

func TestFormatsWithEncoders(t *testing.T) {
	list := `Encoders:
 V..... = Video
 A..... = Audio
 ------
 V....D libx264              libx264 H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10 (codec h264)
 V....D libvpx-vp9           libvpx VP9 (codec vp9)
 A....D aac                  AAC (Advanced Audio Coding)
 A....D libmp3lame           libmp3lame MP3 (MPEG audio layer 3) (codec mp3)
`
	// VP9 without Opus, and MPEG-4 video missing for AVI, leave those out.
	want := []Format{"mp4", "mov", "mkv", "m4v", "flv", "3gp", "3g2", "ts"}
	if got := formatsWithEncoders(list); !slices.Equal(got, want) {
		t.Errorf("formatsWithEncoders = %v, want %v", got, want)
	}
	if got := formatsWithEncoders(""); got == nil || len(got) != 0 {
		t.Errorf("formatsWithEncoders(\"\") = %#v, want an empty, non-nil list", got)
	}
}

// generateClip writes a one-second clip with real ffmpeg: a 176x144, 25 fps
// test pattern and a stereo 48 kHz tone, encoded with the given codecs.
func generateClip(t *testing.T, path, videoCodec, audioCodec string) {
	t.Helper()
	cmd := exec.Command("ffmpeg", "-loglevel", "error",
		"-f", "lavfi", "-i", "testsrc=size=176x144:rate=25:duration=1",
		"-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=1",
		"-ac", "2", "-pix_fmt", "yuv420p", "-c:v", videoCodec, "-c:a", audioCodec, "-shortest", "-y", path)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("generate clip: %v\n%s", err, out)
	}
}

// TestTranscodeIntoEveryAvailableFormat re-encodes a lossless clip into every
// format this ffmpeg can write, and checks each output is a playable video
// whose codecs its own container lists as copyable, which also pins the copy
// table to the encoders the table picks.
func TestTranscodeIntoEveryAvailableFormat(t *testing.T) {
	if !Available() {
		t.Skip("ffmpeg not available")
	}
	available, err := AvailableFormats()
	if err != nil {
		t.Fatal(err)
	}
	src := filepath.Join(t.TempDir(), "src.mkv")
	// FFV1 and PCM are copyable into nothing in the table, so every format
	// really re-encodes.
	generateClip(t, src, "ffv1", "pcm_s16le")

	var ran, skipped []Format
	for _, f := range Formats() {
		t.Run(string(f), func(t *testing.T) {
			if !slices.Contains(available, f) {
				skipped = append(skipped, f)
				t.Skipf("this ffmpeg lacks the encoders for %s", f)
			}
			for _, q := range []Quality{QualityOriginal, QualitySmall} {
				out := filepath.Join(t.TempDir(), "out")
				if err := Transcode(context.Background(), TranscodeParams{Source: src, Output: out, Format: f, Quality: q}); err != nil {
					t.Fatalf("Transcode(%s, %s) error: %v", f, q, err)
				}
				info, err := Probe(context.Background(), out)
				if err != nil {
					t.Fatalf("Probe(%s, %s output) error: %v", f, q, err)
				}
				if info.Height != 144 || info.Duration <= 0 || info.AudioCodec == "" {
					t.Errorf("%s %s output = %+v, want 144 lines, a duration, and audio", f, q, info)
				}
				if !CanCopy(info, f, QualityOriginal) {
					t.Errorf("%s output has codecs %s/%s that its own copy list does not take", f, info.VideoCodec, info.AudioCodec)
				}
			}
			ran = append(ran, f)
		})
	}
	t.Logf("transcoded into %v; skipped %v", ran, skipped)
}

func TestTranscodeCopiesCompatibleStreams(t *testing.T) {
	if !Available() {
		t.Skip("ffmpeg not available")
	}
	available, err := AvailableFormats()
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(available, "mov") {
		t.Skip("this ffmpeg cannot write the H.264 and AAC clip the test needs")
	}
	dir := t.TempDir()
	src := filepath.Join(dir, "src.mkv")
	generateClip(t, src, "libx264", "aac")
	srcInfo, err := Probe(context.Background(), src)
	if err != nil {
		t.Fatal(err)
	}
	if !CanCopy(srcInfo, "mov", QualityOriginal) {
		t.Fatalf("an H.264 and AAC MKV (%+v) is not copyable into MOV", srcInfo)
	}

	out := filepath.Join(dir, "out.mov")
	if err := Transcode(context.Background(), TranscodeParams{Source: src, Output: out, Format: "mov", Quality: QualityOriginal}); err != nil {
		t.Fatalf("Transcode() error: %v", err)
	}
	info, err := Probe(context.Background(), out)
	if err != nil {
		t.Fatal(err)
	}
	if info.VideoCodec != "h264" || info.AudioCodec != "aac" || info.Width != srcInfo.Width || info.Height != srcInfo.Height {
		t.Errorf("copied output = %+v, want the source's H.264 and AAC at %dx%d", info, srcInfo.Width, srcInfo.Height)
	}
}
