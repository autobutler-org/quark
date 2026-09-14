// Package ffmpegutil wraps video inspection, thumbnails, and trimming behind the
// VideoProcessor interface, with CLIProcessor as the ffmpeg/ffprobe-backed
// implementation.
package ffmpegutil

import (
	"context"
	"time"
)

type MediaInfo struct {
	Duration time.Duration
	Width    int
	Height   int
	Codec    string
	Format   string
	Bitrate  int64
}

type VideoProcessor interface {
	Run(ctx context.Context, args ...string) error
	Probe(ctx context.Context, path string) (*MediaInfo, error)
	ExtractThumbnail(ctx context.Context, src, dst string, at time.Duration) error
	Trim(ctx context.Context, src, dst string, start, end time.Duration) error
	Available() bool
}

// ProcessorError carries the arguments and stderr of a failed ffmpeg run so the
// caller can report what the tool actually complained about.
type ProcessorError struct {
	Args   []string
	Stderr string
	Err    error
}

// CLIProcessor is the VideoProcessor backed by the ffmpeg and ffprobe binaries
// on PATH.
type CLIProcessor struct {
	ffmpegPath  string
	ffprobePath string
}

func NewCLIProcessor() *CLIProcessor {
	return &CLIProcessor{
		ffmpegPath:  "ffmpeg",
		ffprobePath: "ffprobe",
	}
}

func NewCLIProcessorAt(ffmpegPath, ffprobePath string) *CLIProcessor {
	return &CLIProcessor{
		ffmpegPath:  ffmpegPath,
		ffprobePath: ffprobePath,
	}
}
