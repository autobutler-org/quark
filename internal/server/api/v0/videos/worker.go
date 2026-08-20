package v0_videos

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/autobutler-org/autobutler/internal/db"
	"github.com/autobutler-org/autobutler/pkg/util/storageutil"
	"github.com/autobutler-org/autobutler/pkg/util/videoutil"
)

// transcodePollInterval is how often the worker checks for new pending jobs.
const transcodePollInterval = 5 * time.Second

// transcodeParams is the JSON stored in video_jobs.params for transcode jobs.
type transcodeParams struct {
	Preset string `json:"preset"`
}

// StartWorker launches the background video job processor. It blocks on ctx
// and should be run in a goroutine.
func StartWorker(ctx context.Context, database *db.DatabaseSqlc, filesDir string) {
	slog.Info("video worker: started")
	ticker := time.NewTicker(transcodePollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			slog.Info("video worker: stopping")
			return
		case <-ticker.C:
			processOnePendingJob(ctx, database, filesDir)
		}
	}
}

// processOnePendingJob picks up the oldest pending job and runs it.
func processOnePendingJob(ctx context.Context, database *db.DatabaseSqlc, filesDir string) {
	jobs, err := database.Queries.ListPendingVideoJobs(ctx)
	if err != nil || len(jobs) == 0 {
		return
	}
	job := jobs[0]

	// Claim the job by setting status to running.
	if err := database.Queries.UpdateVideoJobStatus(ctx, db.UpdateVideoJobStatusParams{
		ID:            job.ID,
		Status:        "running",
		Progress:      0,
		OutputRelPath: "",
		ErrorMessage:  "",
	}); err != nil {
		slog.Error("video worker: failed to claim job", "id", job.ID, "err", err)
		return
	}

	slog.Info("video worker: running job", "id", job.ID, "type", job.JobType, "input", job.InputRelPath)
	outRel, err := runJob(ctx, database, job, filesDir)
	if err != nil {
		slog.Error("video worker: job failed", "id", job.ID, "err", err)
		_ = database.Queries.UpdateVideoJobStatus(ctx, db.UpdateVideoJobStatusParams{
			ID:            job.ID,
			Status:        "failed",
			Progress:      0,
			OutputRelPath: "",
			ErrorMessage:  err.Error(),
		})
		return
	}

	_ = database.Queries.UpdateVideoJobStatus(ctx, db.UpdateVideoJobStatusParams{
		ID:            job.ID,
		Status:        "completed",
		Progress:      1.0,
		OutputRelPath: outRel,
		ErrorMessage:  "",
	})
	slog.Info("video worker: job completed", "id", job.ID, "output", outRel)
}

// runJob executes the work for a single job and returns the output relative path.
func runJob(ctx context.Context, database *db.DatabaseSqlc, job db.VideoJob, filesDir string) (string, error) {
	cleanFilesDir := filepath.Clean(filesDir)

	if job.DeviceSerial != "" {
		// TODO: device serial resolution — for now fall back to default dir.
	}

	fullInput := filepath.Join(cleanFilesDir, job.InputRelPath)

	switch job.JobType {
	case "transcode":
		var p transcodeParams
		if err := json.Unmarshal([]byte(job.Params), &p); err != nil {
			return "", fmt.Errorf("parse params: %w", err)
		}

		preset := videoutil.TranscodePreset(p.Preset)
		ext := outputExtForPreset(preset)
		stem := strings.TrimSuffix(filepath.Base(job.InputRelPath), filepath.Ext(job.InputRelPath))
		outName := stem + "_converted" + ext
		outFull := storageutil.GetNonConflictingPath(filepath.Join(filepath.Dir(fullInput), outName))
		outRel, err := filepath.Rel(cleanFilesDir, outFull)
		if err != nil {
			return "", fmt.Errorf("resolve output path: %w", err)
		}

		// Probe duration for progress reporting.
		var totalSecs float64
		if info, err := videoutil.Probe(ctx, fullInput); err == nil {
			totalSecs = info.Duration.Seconds()
		}

		// Run ffmpeg with -progress pipe to stderr for progress updates.
		if err := transcodeWithProgress(ctx, database, job.ID, fullInput, preset, outFull, totalSecs); err != nil {
			return "", err
		}
		return outRel, nil

	default:
		return "", fmt.Errorf("unknown job type: %q", job.JobType)
	}
}

// transcodeWithProgress runs ffmpeg with -progress output and updates job progress in the DB.
func transcodeWithProgress(
	ctx context.Context,
	database *db.DatabaseSqlc,
	jobID int64,
	input string,
	preset videoutil.TranscodePreset,
	output string,
	totalSecs float64,
) error {
	ffmpegPath, err := exec.LookPath("ffmpeg")
	if err != nil {
		return fmt.Errorf("ffmpeg not found: %w", err)
	}

	args := buildTranscodeArgs(input, preset, output)
	// -progress pipe:2 writes structured progress to stderr.
	args = append([]string{"-progress", "pipe:2"}, args...)
	cmd := exec.CommandContext(ctx, ffmpegPath, args...)

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("stderr pipe: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("ffmpeg start: %w", err)
	}

	// Parse progress lines: "out_time_ms=<microseconds>" from -progress output.
	scanner := bufio.NewScanner(stderr)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "out_time_ms=") {
			msStr := strings.TrimPrefix(line, "out_time_ms=")
			if us, parseErr := strconv.ParseFloat(msStr, 64); parseErr == nil && totalSecs > 0 {
				progress := (us / 1_000_000) / totalSecs
				if progress > 1 {
					progress = 1
				}
				_ = database.Queries.UpdateVideoJobStatus(ctx, db.UpdateVideoJobStatusParams{
					ID:            jobID,
					Status:        "running",
					Progress:      progress,
					OutputRelPath: "",
					ErrorMessage:  "",
				})
			}
		}
	}

	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("ffmpeg: %w", err)
	}
	return nil
}

// buildTranscodeArgs returns ffmpeg args for a preset (without -progress or -y).
func buildTranscodeArgs(input string, preset videoutil.TranscodePreset, output string) []string {
	base := []string{"-i", input}
	var enc []string
	switch preset {
	case videoutil.PresetH264480p:
		enc = []string{"-vf", "scale=-2:480", "-c:v", "libx264", "-crf", "23", "-preset", "fast", "-c:a", "aac", "-b:a", "128k"}
	case videoutil.PresetH264720p:
		enc = []string{"-vf", "scale=-2:720", "-c:v", "libx264", "-crf", "23", "-preset", "fast", "-c:a", "aac", "-b:a", "128k"}
	case videoutil.PresetH2641080p:
		enc = []string{"-vf", "scale=-2:1080", "-c:v", "libx264", "-crf", "23", "-preset", "fast", "-c:a", "aac", "-b:a", "192k"}
	case videoutil.PresetWebM720p:
		enc = []string{"-vf", "scale=-2:720", "-c:v", "libvpx-vp9", "-crf", "33", "-b:v", "0", "-c:a", "libopus", "-b:a", "128k"}
	default:
		enc = []string{"-vf", "scale=-2:720", "-c:v", "libx264", "-crf", "23", "-preset", "fast", "-c:a", "aac", "-b:a", "128k"}
	}
	return append(append(base, enc...), "-y", output)
}

// outputExtForPreset returns the file extension for the output of a preset.
func outputExtForPreset(preset videoutil.TranscodePreset) string {
	if preset == videoutil.PresetWebM720p {
		return ".webm"
	}
	return ".mp4"
}
