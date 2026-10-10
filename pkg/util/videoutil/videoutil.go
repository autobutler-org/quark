// Package videoutil probes, trims, and remuxes video files with sprocket, in
// pure Go: none of the three decodes a frame, so they work for every codec and
// need nothing installed on the device.
//
// Keyframe is the one that decodes, for video thumbnails, and it is pure Go
// too. sprocket carries a decoder for AV1 and VP8 only, so every other codec
// answers ErrNoDecoder and is left for a client to render.
package videoutil

import (
	"context"
	"errors"
	"fmt"
	"image"
	"os"
	"path/filepath"
	"time"

	"github.com/autobutler-org/sprocket/pkg/sprocket"
)

// VideoInfo is what Probe reports about a video file.
type VideoInfo struct {
	Duration time.Duration
	Width    int
	Height   int
	// VideoCodec and AudioCodec use ffprobe's names ("h264", "ac3", "flac"),
	// which is what the API has always returned.
	VideoCodec string
	AudioCodec string
	Bitrate    int64
	Framerate  float64
	// Rotation is in degrees (0, 90, 180, 270) counterclockwise, ffprobe's
	// display-matrix convention: a phone's portrait video reports 270.
	Rotation int
}

// Format is a video container Remux writes, named by its file extension
// without the dot, such as "mp4" or "mkv".
type Format string

// ErrCannotTrim is returned by Trim for a source it cannot cut on the device:
// an MPEG-TS file, or a fragmented MP4.
var ErrCannotTrim = errors.New("this video's container can't be trimmed")

// ErrNoDecoder is returned by Keyframe for a video whose codec the device has
// no decoder for, which is every one but AV1 and VP8, and for a frame over the
// decoder's size cap. The file is fine; the device just cannot picture it.
var ErrNoDecoder = errors.New("this video's codec can't be decoded on the device")

// Formats returns every Format Remux writes, in the order clients list them.
func Formats() []Format {
	formats := make([]Format, 0, len(formatSpecs))
	for _, spec := range formatSpecs {
		formats = append(formats, Format(spec.container))
	}
	return formats
}

// Valid reports whether f is a Format Remux writes.
func (f Format) Valid() bool {
	_, ok := lookupFormat(f)
	return ok
}

// Label is f's display name, such as "MP4" or "WebM", and "" for a Format
// that is not Valid.
func (f Format) Label() string {
	spec, _ := lookupFormat(f)
	return spec.label
}

// Probe reports the duration, dimensions, codecs, bitrate, framerate, and
// rotation of the video at filePath. It reads headers only. ctx is accepted
// for the callers' sake; a probe costs a few reads and cannot be interrupted.
func Probe(_ context.Context, filePath string) (*VideoInfo, error) {
	info, err := probe(filePath)
	if err != nil {
		return nil, err
	}
	return &VideoInfo{
		Duration:   info.Duration,
		Width:      info.Width,
		Height:     info.Height,
		VideoCodec: ffprobeCodecName(info.VideoCodec),
		AudioCodec: ffprobeCodecName(info.AudioCodec),
		Bitrate:    int64(info.Bitrate),
		Framerate:  info.FrameRate,
		Rotation:   counterclockwise(info.Rotation),
	}, nil
}

// Targets returns the Formats the video at filePath can be remuxed into, in
// Formats order: every one sprocket.CanRemux allows for its codecs and its
// container family, leaving out its own format, which would only copy the
// file. Remux reads the same table.
func Targets(filePath string) ([]Format, error) {
	info, err := probe(filePath)
	if err != nil {
		return nil, err
	}
	own := formatOf(filePath)
	targets := []Format{}
	for _, spec := range formatSpecs {
		if Format(spec.container) != own && sprocket.CanRemux(info, spec.container) {
			targets = append(targets, Format(spec.container))
		}
	}
	return targets, nil
}

// TrimFormat is the Format Trim writes the source at path into: its own when
// Remux writes it, and MP4 otherwise.
func TrimFormat(path string) Format {
	if own := formatOf(path); own.Valid() {
		return own
	}
	return "mp4"
}

// TrimParams describes one Trim.
type TrimParams struct {
	Source string
	// Output is created, or truncated, and removed again if the trim fails.
	Output     string
	Start, End time.Duration
}

// TrimResult is what a Trim produced.
type TrimResult struct {
	// Start is where the output is shown from on the source's timeline. It is
	// the requested start, with the frames back to the keyframe before it kept
	// but hidden, except where sprocket has nothing to hide them behind or
	// nothing to hide: a TS output, which shows them and reports the keyframe,
	// or a start before the first keyframe or past the last video frame, which
	// takes that keyframe.
	Start time.Duration
}

// Trim copies [Start, End) of Source into Output, in TrimFormat(Source),
// without re-encoding. The result reports where the output is shown from. A
// source it cannot cut returns ErrCannotTrim.
func Trim(ctx context.Context, params TrimParams) (TrimResult, error) {
	var start time.Duration
	err := writeFrom(ctx, params.Source, params.Output, nil, func(src *os.File, size int64, w *progressWriter) error {
		var err error
		start, err = sprocket.Trim(src, size, w, sprocket.Container(TrimFormat(params.Source)), params.Start, params.End)
		return err
	})
	if errors.Is(err, sprocket.ErrUnsupportedContainer) || errors.Is(err, sprocket.ErrIncompatible) {
		return TrimResult{}, fmt.Errorf("%w: %w", ErrCannotTrim, err)
	}
	if err != nil {
		return TrimResult{}, err
	}
	return TrimResult{Start: start}, nil
}

// RemuxParams describes one Remux.
type RemuxParams struct {
	// Source is the video to read.
	Source string
	// Output is where the result is written, and removed again if the remux
	// fails. Its extension does not matter: the container is Format.
	Output string
	Format Format
	// OnProgress, when non-nil, is called with the fraction of the source
	// written so far, in [0, 1], from the goroutine running Remux.
	OnProgress func(fraction float64)
}

// Remux copies Source's video and audio streams into Output as Format without
// re-encoding them. It stops with ctx's error when ctx is done. A source whose
// codecs Format cannot hold is refused; Targets names the formats that fit.
func Remux(ctx context.Context, params RemuxParams) error {
	if !params.Format.Valid() {
		return fmt.Errorf("unknown remux format %q", params.Format)
	}
	return writeFrom(ctx, params.Source, params.Output, params.OnProgress, func(src *os.File, size int64, w *progressWriter) error {
		return sprocket.Remux(src, size, w, sprocket.Container(params.Format))
	})
}

// KeyframeParams describes one Keyframe.
type KeyframeParams struct {
	// Source is the video to read.
	Source string
	// At is the time the keyframe is taken nearest to.
	At time.Duration
}

// KeyframeResult is what a Keyframe decoded.
type KeyframeResult struct {
	// Image is the keyframe at its own size, the way up a player shows it:
	// the rotation an MP4 track carries is already applied.
	Image image.Image
}

// Keyframe decodes the keyframe of Source nearest At, without running
// anything outside the process. It reads that one sample rather than the
// file, and holds one decoded frame. A time past the end takes the last
// keyframe. A codec with no decoder returns ErrNoDecoder.
func Keyframe(params KeyframeParams) (KeyframeResult, error) {
	src, err := os.Open(params.Source)
	if err != nil {
		return KeyframeResult{}, err
	}
	defer src.Close()
	stat, err := src.Stat()
	if err != nil {
		return KeyframeResult{}, err
	}
	frame, err := sprocket.Thumbnail(src, stat.Size(), params.At, sprocket.ThumbnailOptions{})
	if errors.Is(err, sprocket.ErrUnsupportedCodec) {
		return KeyframeResult{}, fmt.Errorf("%w: %w", ErrNoDecoder, err)
	}
	if err != nil {
		return KeyframeResult{}, fmt.Errorf("keyframe of %s: %w", filepath.Base(params.Source), err)
	}
	return KeyframeResult{Image: frame.Image}, nil
}
