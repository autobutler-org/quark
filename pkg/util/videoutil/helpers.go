package videoutil

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

// scaleFilter caps the output height at maxHeight without ever upscaling, and
// rounds it down to an even number because libx264 and libvpx reject odd
// dimensions. The comma inside min() is escaped for ffmpeg's filtergraph
// parser; no shell is involved, so the backslash reaches ffmpeg as written.
func scaleFilter(maxHeight int) string {
	return fmt.Sprintf(`scale=-2:trunc(min(ih\,%d)/2)*2`, maxHeight)
}

// evenFilter keeps the source size but rounds each side down to an even
// number, which yuv420p encoders require.
const evenFilter = "scale=trunc(iw/2)*2:trunc(ih/2)*2"

// smallHeight is the most lines QualitySmall keeps.
const smallHeight = 480

// transcodeArgs builds the ffmpeg arguments for one Transcode. copyStreams
// copies the kept streams instead of encoding them.
func transcodeArgs(params TranscodeParams, spec formatSpec, copyStreams bool) []string {
	args := []string{
		"-progress", "pipe:1", "-nostats", "-loglevel", "error",
		"-i", params.Source,
		// The first video stream, and the first audio stream if there is one.
		"-map", "0:v:0", "-map", "0:a:0?",
	}
	if copyStreams {
		args = append(args, "-c", "copy")
	} else {
		filter := evenFilter
		if params.Quality == QualitySmall {
			filter = scaleFilter(smallHeight)
		}
		// yuv420p is the pixel format every encoder in the table accepts and
		// every player decodes.
		args = append(args, "-vf", filter, "-pix_fmt", "yuv420p", "-c:v", spec.video.encoder)
		args = append(args, spec.video.flags(params.Quality)...)
		args = append(args, "-c:a", spec.audio.encoder)
		args = append(args, spec.audio.flags(params.Quality)...)
	}
	return append(args, "-f", spec.muxer, "-y", params.Output)
}

// lookupFormat finds f's row in formatSpecs.
func lookupFormat(f Format) (formatSpec, bool) {
	i := slices.IndexFunc(formatSpecs, func(spec formatSpec) bool { return spec.format == f })
	if i < 0 {
		return formatSpec{}, false
	}
	return formatSpecs[i], true
}

// flags returns the encoder options for q.
func (c codecSpec) flags(q Quality) []string {
	if q == QualitySmall {
		return c.small
	}
	return c.original
}

// formatsWithEncoders returns the Formats, in table order, whose video and
// audio encoders both appear in the output of ffmpeg -encoders. Each encoder
// line is flags then name; legend and header lines add names no format uses.
func formatsWithEncoders(encoderList string) []Format {
	encoders := map[string]bool{}
	for _, line := range strings.Split(encoderList, "\n") {
		if fields := strings.Fields(line); len(fields) >= 2 {
			encoders[fields[1]] = true
		}
	}
	formats := []Format{}
	for _, spec := range formatSpecs {
		if encoders[spec.video.encoder] && encoders[spec.audio.encoder] {
			formats = append(formats, spec.format)
		}
	}
	return formats
}

// parseProgressLine reads the encoded position from one line of ffmpeg's
// -progress output. out_time_us is preferred; out_time_ms is the fallback and,
// despite its name, ffmpeg reports it in microseconds too. "N/A" and every
// other key report false.
func parseProgressLine(line string) (time.Duration, bool) {
	key, value, ok := strings.Cut(strings.TrimSpace(line), "=")
	if !ok || (key != "out_time_us" && key != "out_time_ms") {
		return 0, false
	}
	us, err := strconv.ParseInt(value, 10, 64)
	if err != nil || us < 0 {
		return 0, false
	}
	return time.Duration(us) * time.Microsecond, true
}

// formatTimestamp converts a Duration to an ffmpeg timestamp string (HH:MM:SS.mmm).
func formatTimestamp(d time.Duration) string {
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	s := int(d.Seconds()) % 60
	ms := int(d.Milliseconds()) % 1000
	return fmt.Sprintf("%02d:%02d:%02d.%03d", h, m, s, ms)
}
