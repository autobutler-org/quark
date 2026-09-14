package ffmpegutil

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func requireFFmpeg(t *testing.T) {
	t.Helper()
	if _, err := exec.LookPath("ffmpeg"); err != nil {
		t.Skip("ffmpeg not found on PATH, skipping")
	}
}

func createTestVideo(t *testing.T, dir string) string {
	t.Helper()
	path := filepath.Join(dir, "test.mp4")
	cmd := exec.Command("ffmpeg",
		"-f", "lavfi",
		"-i", "testsrc=duration=3:size=320x240:rate=25",
		"-f", "lavfi",
		"-i", "sine=frequency=440:duration=3",
		"-c:v", "libx264",
		"-c:a", "aac",
		"-pix_fmt", "yuv420p",
		"-y",
		path,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("failed to create test video: %v\n%s", err, out)
	}
	return path
}

func TestNewCLIProcessor(t *testing.T) {
	p := NewCLIProcessor()
	if p.ffmpegPath != "ffmpeg" {
		t.Errorf("expected ffmpegPath 'ffmpeg', got %q", p.ffmpegPath)
	}
	if p.ffprobePath != "ffprobe" {
		t.Errorf("expected ffprobePath 'ffprobe', got %q", p.ffprobePath)
	}
}

func TestNewCLIProcessorAt(t *testing.T) {
	p := NewCLIProcessorAt("/usr/local/bin/ffmpeg", "/usr/local/bin/ffprobe")
	if p.ffmpegPath != "/usr/local/bin/ffmpeg" {
		t.Errorf("expected custom ffmpegPath, got %q", p.ffmpegPath)
	}
}

func TestAvailable(t *testing.T) {
	p := NewCLIProcessor()
	got := p.Available()
	_, err := exec.LookPath("ffmpeg")
	want := err == nil
	if got != want {
		t.Errorf("Available() = %v, want %v", got, want)
	}
}

func TestAvailable_Missing(t *testing.T) {
	p := NewCLIProcessorAt("/nonexistent/ffmpeg", "/nonexistent/ffprobe")
	if p.Available() {
		t.Error("Available() should return false for nonexistent binary")
	}
}

func TestRun_InvalidArgs(t *testing.T) {
	requireFFmpeg(t)
	p := NewCLIProcessor()
	err := p.Run(context.Background(), "-i", "/nonexistent/file.mp4")
	if err == nil {
		t.Fatal("expected error for nonexistent input")
	}
	var pe *ProcessorError
	if ok := errorAs(err, &pe); !ok {
		t.Fatalf("expected *ProcessorError, got %T", err)
	}
	if pe.Stderr == "" {
		t.Error("expected non-empty stderr in ProcessorError")
	}
}

func TestProbe(t *testing.T) {
	requireFFmpeg(t)
	dir := t.TempDir()
	videoPath := createTestVideo(t, dir)

	p := NewCLIProcessor()
	info, err := p.Probe(context.Background(), videoPath)
	if err != nil {
		t.Fatalf("Probe failed: %v", err)
	}

	if info.Width != 320 || info.Height != 240 {
		t.Errorf("expected 320x240, got %dx%d", info.Width, info.Height)
	}
	if info.Duration < 2*time.Second || info.Duration > 4*time.Second {
		t.Errorf("expected ~3s duration, got %v", info.Duration)
	}
	if info.Codec != "h264" {
		t.Errorf("expected codec h264, got %q", info.Codec)
	}
}

func TestProbe_NonexistentFile(t *testing.T) {
	requireFFmpeg(t)
	p := NewCLIProcessor()
	_, err := p.Probe(context.Background(), "/nonexistent/file.mp4")
	if err == nil {
		t.Fatal("expected error for nonexistent file")
	}
}

func TestExtractThumbnail(t *testing.T) {
	requireFFmpeg(t)
	dir := t.TempDir()
	videoPath := createTestVideo(t, dir)
	thumbPath := filepath.Join(dir, "thumb.jpg")

	p := NewCLIProcessor()
	if err := p.ExtractThumbnail(context.Background(), videoPath, thumbPath, 1*time.Second); err != nil {
		t.Fatalf("ExtractThumbnail failed: %v", err)
	}

	stat, err := os.Stat(thumbPath)
	if err != nil {
		t.Fatalf("thumbnail not created: %v", err)
	}
	if stat.Size() == 0 {
		t.Error("thumbnail file is empty")
	}
}

func TestTrim(t *testing.T) {
	requireFFmpeg(t)
	dir := t.TempDir()
	videoPath := createTestVideo(t, dir)
	outPath := filepath.Join(dir, "trimmed.mp4")

	p := NewCLIProcessor()
	if err := p.Trim(context.Background(), videoPath, outPath, 0, 1*time.Second); err != nil {
		t.Fatalf("Trim failed: %v", err)
	}

	stat, err := os.Stat(outPath)
	if err != nil {
		t.Fatalf("trimmed file not created: %v", err)
	}
	if stat.Size() == 0 {
		t.Error("trimmed file is empty")
	}

	info, err := p.Probe(context.Background(), outPath)
	if err != nil {
		t.Fatalf("Probe trimmed file failed: %v", err)
	}
	if info.Duration > 2*time.Second {
		t.Errorf("expected trimmed duration <=2s, got %v", info.Duration)
	}
}

func TestFormatDuration(t *testing.T) {
	tests := []struct {
		d    time.Duration
		want string
	}{
		{0, "00:00:00.000"},
		{1500 * time.Millisecond, "00:00:01.500"},
		{time.Hour + 2*time.Minute + 3*time.Second, "01:02:03.000"},
		{90 * time.Second, "00:01:30.000"},
	}
	for _, tt := range tests {
		got := formatDuration(tt.d)
		if got != tt.want {
			t.Errorf("formatDuration(%v) = %q, want %q", tt.d, got, tt.want)
		}
	}
}

func TestProcessorError(t *testing.T) {
	err := &ProcessorError{
		Args:   []string{"-i", "test.mp4"},
		Stderr: "some error output",
		Err:    os.ErrNotExist,
	}
	msg := err.Error()
	if msg == "" {
		t.Error("expected non-empty error message")
	}
	if err.Unwrap() != os.ErrNotExist {
		t.Error("Unwrap should return the wrapped error")
	}
}

func TestContextCancellation(t *testing.T) {
	requireFFmpeg(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	p := NewCLIProcessor()
	err := p.Run(ctx, "-version")
	if err == nil {
		t.Error("expected error with cancelled context")
	}
}

// errorAs is a helper to avoid importing errors in the test file.
func errorAs(err error, target any) bool {
	if pe, ok := target.(**ProcessorError); ok {
		if e, ok2 := err.(*ProcessorError); ok2 {
			*pe = e
			return true
		}
	}
	return false
}
