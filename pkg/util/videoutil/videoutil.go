// Package videoutil provides a thin wrapper around ffmpeg and ffprobe for
// video probing, frame extraction, trimming, and transcoding.
//
// All functions return an error if ffmpeg/ffprobe is not available; callers
// should check [Available] at startup and return 501 Not Implemented for
// video-specific endpoints when the tools are missing.
package videoutil

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"os/exec"
	"slices"
	"strings"
	"time"
)

// VideoInfo holds the metadata returned by ffprobe for a single video file.
type VideoInfo struct {
	Duration   time.Duration
	Width      int
	Height     int
	VideoCodec string
	AudioCodec string
	Bitrate    int64
	Framerate  float64
	Rotation   int // degrees (0, 90, 180, 270)
}

// Format is a video container Transcode writes, named by its file extension
// without the dot, such as "mov" or "mkv".
type Format string

// Quality is how Transcode trades file size for fidelity.
type Quality string

const (
	// QualityOriginal keeps the source resolution.
	QualityOriginal Quality = "original"
	// QualitySmall caps the height at 480 lines, never scaling up, and encodes
	// at a lower bitrate.
	QualitySmall Quality = "small"
)

// Formats returns every Format Transcode knows, in the order clients list
// them. A given ffmpeg build may lack the encoders for some; see
// [AvailableFormats].
func Formats() []Format {
	formats := make([]Format, 0, len(formatSpecs))
	for _, spec := range formatSpecs {
		formats = append(formats, spec.format)
	}
	return formats
}

// Valid reports whether f is a Format Transcode knows.
func (f Format) Valid() bool {
	_, ok := lookupFormat(f)
	return ok
}

// Label is f's display name, such as "MOV" or "WebM", and "" for a Format
// that is not Valid.
func (f Format) Label() string {
	spec, _ := lookupFormat(f)
	return spec.label
}

// Valid reports whether q is QualityOriginal or QualitySmall.
func (q Quality) Valid() bool {
	return q == QualityOriginal || q == QualitySmall
}

// AvailableFormats returns the Formats whose video and audio encoders this
// ffmpeg build has, in Formats order. A successful answer is cached for the
// life of the process; a failure is not, so installing ffmpeg later works.
func AvailableFormats() ([]Format, error) {
	availableMu.Lock()
	defer availableMu.Unlock()
	if available != nil {
		return available, nil
	}
	ffmpegPath, err := exec.LookPath("ffmpeg")
	if err != nil {
		return nil, fmt.Errorf("ffmpeg not found: %w", err)
	}
	// The encoder list is a few kilobytes that ffmpeg, not a user, sizes.
	out, err := exec.Command(ffmpegPath, "-hide_banner", "-encoders").Output()
	if err != nil {
		return nil, fmt.Errorf("ffmpeg -encoders: %w", err)
	}
	available = formatsWithEncoders(string(out))
	return available, nil
}

// CanCopy reports whether Transcode copies the streams info describes into f
// unchanged instead of re-encoding them. That happens only at QualityOriginal,
// and only when f's container accepts the source's video codec and its audio
// codec, if it has audio.
func CanCopy(info *VideoInfo, f Format, q Quality) bool {
	spec, ok := lookupFormat(f)
	if !ok || q != QualityOriginal || info == nil || info.VideoCodec == "" {
		return false
	}
	return slices.Contains(spec.copyVideo, info.VideoCodec) &&
		(info.AudioCodec == "" || slices.Contains(spec.copyAudio, info.AudioCodec))
}

// TranscodeParams describes one Transcode.
type TranscodeParams struct {
	// Source is the video to read.
	Source string
	// Output is where the result is written. Its extension does not matter:
	// the container is chosen from Format.
	Output  string
	Format  Format
	Quality Quality
	// OnProgress, when non-nil, is called with the fraction of the source
	// written so far, in [0, 1], from the goroutine running Transcode.
	OnProgress func(fraction float64)
}

// Available returns true if both ffmpeg and ffprobe are found on PATH.
func Available() bool {
	_, errMpeg := exec.LookPath("ffmpeg")
	_, errProbe := exec.LookPath("ffprobe")
	return errMpeg == nil && errProbe == nil
}

// Version returns the ffmpeg version string (first line), or an error if not installed.
func Version() (string, error) {
	path, err := exec.LookPath("ffmpeg")
	if err != nil {
		return "", fmt.Errorf("ffmpeg not found on PATH: %w", err)
	}
	out, err := exec.Command(path, "-version").Output()
	if err != nil {
		return "", fmt.Errorf("ffmpeg -version: %w", err)
	}
	for _, line := range []byte(out) {
		_ = line
		break
	}
	// Return first line only.
	s := string(out)
	for i, c := range s {
		if c == '\n' {
			return s[:i], nil
		}
	}
	return s, nil
}

// ExtractFrame writes a single JPEG frame at timestamp to outPath.
// outPath should not already exist; use storageutil.GetNonConflictingPath beforehand.
func ExtractFrame(ctx context.Context, filePath string, timestamp time.Duration, outPath string) error {
	ffmpegPath, err := exec.LookPath("ffmpeg")
	if err != nil {
		return fmt.Errorf("ffmpeg not found: %w", err)
	}
	ts := formatTimestamp(timestamp)
	cmd := exec.CommandContext(ctx, ffmpegPath,
		"-ss", ts,
		"-i", filePath,
		"-frames:v", "1",
		"-q:v", "2",
		"-y",
		outPath,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg extract frame: %w\n%s", err, out)
	}
	return nil
}

// Trim extracts the clip [startTime, endTime) from filePath and writes it to
// outPath. Uses stream copy when possible (fast, lossless).
func Trim(ctx context.Context, filePath string, startTime, endTime time.Duration, outPath string) error {
	ffmpegPath, err := exec.LookPath("ffmpeg")
	if err != nil {
		return fmt.Errorf("ffmpeg not found: %w", err)
	}
	duration := endTime - startTime
	if duration <= 0 {
		return fmt.Errorf("endTime must be after startTime")
	}
	cmd := exec.CommandContext(ctx, ffmpegPath,
		"-ss", formatTimestamp(startTime),
		"-i", filePath,
		"-t", formatTimestamp(duration),
		"-c", "copy",
		"-avoid_negative_ts", "make_zero",
		"-y",
		outPath,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg trim: %w\n%s", err, out)
	}
	return nil
}

// Transcode writes Source to Output as Format. When [CanCopy] holds it copies
// the first video and audio streams unchanged, which takes seconds rather than
// the hours a re-encode of a large file can; otherwise it re-encodes them with
// Format's encoders at Quality. Only those two streams are kept, so subtitle
// and data streams a container cannot hold never fail the run.
func Transcode(ctx context.Context, params TranscodeParams) error {
	spec, ok := lookupFormat(params.Format)
	if !ok {
		return fmt.Errorf("unknown transcode format %q", params.Format)
	}
	if !params.Quality.Valid() {
		return fmt.Errorf("unknown transcode quality %q", params.Quality)
	}
	ffmpegPath, err := exec.LookPath("ffmpeg")
	if err != nil {
		return fmt.Errorf("ffmpeg not found: %w", err)
	}

	// The probe gives the duration progress is measured against and the codecs
	// that decide whether the streams can be copied. A source it cannot read
	// still transcodes: re-encoded, with no progress reported.
	info, probeErr := Probe(ctx, params.Source)
	copyStreams := probeErr == nil && CanCopy(info, params.Format, params.Quality)
	var total time.Duration
	if probeErr == nil {
		total = info.Duration
	}

	cmd := exec.CommandContext(ctx, ffmpegPath, transcodeArgs(params, spec, copyStreams)...)
	stderr := &cappedBuffer{max: 16 << 10}
	cmd.Stderr = stderr
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("ffmpeg stdout pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("ffmpeg start: %w", err)
	}

	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		pos, ok := parseProgressLine(scanner.Text())
		if !ok || total <= 0 || params.OnProgress == nil {
			continue
		}
		params.OnProgress(min(float64(pos)/float64(total), 1))
	}
	// Drain whatever the scanner left so ffmpeg never blocks on a full pipe
	// before Wait closes it.
	_, _ = io.Copy(io.Discard, stdout)

	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("ffmpeg transcode: %w: %s", err, strings.TrimSpace(string(stderr.buf)))
	}
	return nil
}
