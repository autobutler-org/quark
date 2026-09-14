package ffmpegutil

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

func (e *ProcessorError) Error() string {
	return fmt.Sprintf("ffmpeg %s failed: %v\nstderr: %s", strings.Join(e.Args, " "), e.Err, e.Stderr)
}

func (e *ProcessorError) Unwrap() error {
	return e.Err
}

func (p *CLIProcessor) Available() bool {
	_, err := exec.LookPath(p.ffmpegPath)
	return err == nil
}

func (p *CLIProcessor) Run(ctx context.Context, args ...string) error {
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, p.ffmpegPath, args...)
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return &ProcessorError{Args: args, Stderr: stderr.String(), Err: err}
	}
	return nil
}

type probeOutput struct {
	Streams []probeStream `json:"streams"`
	Format  probeFormat   `json:"format"`
}

type probeStream struct {
	CodecName string `json:"codec_name"`
	CodecType string `json:"codec_type"`
	Width     int    `json:"width"`
	Height    int    `json:"height"`
}

type probeFormat struct {
	FormatName string `json:"format_name"`
	Duration   string `json:"duration"`
	BitRate    string `json:"bit_rate"`
}

func (p *CLIProcessor) Probe(ctx context.Context, path string) (*MediaInfo, error) {
	var stdout, stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, p.ffprobePath,
		"-v", "quiet",
		"-print_format", "json",
		"-show_format",
		"-show_streams",
		path,
	)
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, &ProcessorError{
			Args:   []string{"-show_format", "-show_streams", path},
			Stderr: stderr.String(),
			Err:    err,
		}
	}

	var out probeOutput
	if err := json.Unmarshal(stdout.Bytes(), &out); err != nil {
		return nil, fmt.Errorf("parse ffprobe output: %w", err)
	}

	info := &MediaInfo{
		Format: out.Format.FormatName,
	}

	if dur, err := strconv.ParseFloat(out.Format.Duration, 64); err == nil {
		info.Duration = time.Duration(dur * float64(time.Second))
	}
	if br, err := strconv.ParseInt(out.Format.BitRate, 10, 64); err == nil {
		info.Bitrate = br
	}

	for _, s := range out.Streams {
		if s.CodecType == "video" {
			info.Codec = s.CodecName
			info.Width = s.Width
			info.Height = s.Height
			break
		}
	}

	return info, nil
}

func (p *CLIProcessor) ExtractThumbnail(ctx context.Context, src, dst string, at time.Duration) error {
	args := []string{
		"-ss", formatDuration(at),
		"-i", src,
		"-vframes", "1",
		"-q:v", "2",
		"-y",
		dst,
	}
	return p.Run(ctx, args...)
}

func (p *CLIProcessor) Trim(ctx context.Context, src, dst string, start, end time.Duration) error {
	args := []string{
		"-ss", formatDuration(start),
		"-to", formatDuration(end),
		"-i", src,
		"-c", "copy",
		"-y",
		dst,
	}
	return p.Run(ctx, args...)
}

func formatDuration(d time.Duration) string {
	totalSeconds := d.Seconds()
	hours := int(totalSeconds) / 3600
	minutes := (int(totalSeconds) % 3600) / 60
	seconds := totalSeconds - float64(hours*3600+minutes*60)
	return fmt.Sprintf("%02d:%02d:%06.3f", hours, minutes, seconds)
}
