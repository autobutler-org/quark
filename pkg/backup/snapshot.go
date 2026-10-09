package backup

import (
	"context"
	"errors"
	"fmt"
	"path"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

func SnapshotBackup(
	ctx context.Context,
	params SnapshotBackupParams,
	sources []SourceDevice,
	target vfs.VFS,
) error {
	job := params.Job
	now := time.Now()

	job.Status = BackupStatusScanning
	job.UpdatedAt = now
	// Best-effort progress persistence; a failed write must not abort the backup.
	_ = params.Store.Update(ctx, job)

	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{
			Kind: eventbus.EventBackupStarted,
			Data: BackupProgressData{JobID: job.ID},
		})
	}

	// Phase 1: scan all sources to count files and bytes.
	job.SourceDevices = make([]SourceDeviceProgress, len(sources))
	for i, src := range sources {
		sdp := SourceDeviceProgress{
			DeviceSerial: src.Serial,
			DeviceName:   src.Name,
		}
		files, bytes, err := scanTree(ctx, src.Files)
		if err != nil {
			return failJob(ctx, params, fmt.Errorf("scan %s: %w", src.Name, err))
		}
		sdp.FilesTotal = files
		sdp.BytesTotal = bytes
		job.TotalFiles += files
		job.TotalBytes += bytes
		job.SourceDevices[i] = sdp
	}
	job.UpdatedAt = time.Now()
	_ = params.Store.Update(ctx, job)

	// Phase 2: copy files from each source to the target.
	job.Status = BackupStatusCopying
	job.UpdatedAt = time.Now()
	_ = params.Store.Update(ctx, job)

	lastPublish := time.Time{}
	for i, src := range sources {
		targetBase := deviceDirName(src.Name, src.Serial)

		err := vfs.Walk(ctx, src.Files, "", func(srcInfo vfs.FileInfo) error {
			if err := ctx.Err(); err != nil {
				return err
			}

			relPath := srcInfo.Path
			targetPath := path.Join(targetBase, relPath)

			if srcInfo.IsDir {
				return target.MkdirAll(ctx, targetPath)
			}

			// Smart skip: if target exists with matching size and mtime >= source, skip.
			if tgtInfo, err := target.Stat(ctx, targetPath); err == nil && !tgtInfo.IsDir {
				if tgtInfo.Size == srcInfo.Size && !tgtInfo.ModTime.Before(srcInfo.ModTime) {
					job.FilesSkipped++
					job.SourceDevices[i].FilesSkipped++
					return nil
				}
			}

			// Acquire IO semaphore before copying to yield to interactive requests.
			if params.IOSemaphore != nil {
				if !params.IOSemaphore.AcquireDefault(ctx) {
					return fmt.Errorf("snapshot: IO semaphore timeout copying %s", relPath)
				}
				defer params.IOSemaphore.Release()
			}

			// The copy lands under its real name only once it is whole.
			if err := vfs.CopyBetween(ctx, src.Files, relPath, target, targetPath, vfs.CopyOptions{}); err != nil {
				return fmt.Errorf("copy %s: %w", relPath, err)
			}

			job.FilesCopied++
			job.BytesCopied += srcInfo.Size
			job.SourceDevices[i].FilesCopied++
			job.SourceDevices[i].BytesCopied += srcInfo.Size

			if job.TotalFiles > 0 {
				job.Progress = float64(job.FilesCopied+job.FilesSkipped) / float64(job.TotalFiles)
			}
			job.UpdatedAt = time.Now()
			_ = params.Store.Update(ctx, job)

			// Throttle WebSocket events to ~2/sec.
			if params.EventBus != nil && time.Since(lastPublish) > 500*time.Millisecond {
				params.EventBus.Publish(eventbus.Event{
					Kind: eventbus.EventBackupProgress,
					Data: BackupProgressData{
						JobID:       job.ID,
						Progress:    job.Progress,
						FilesCopied: job.FilesCopied,
						TotalFiles:  job.TotalFiles,
						BytesCopied: job.BytesCopied,
						TotalBytes:  job.TotalBytes,
						CurrentFile: relPath,
					},
				})
				lastPublish = time.Now()
			}

			return nil
		})

		if err != nil {
			return failJob(ctx, params, fmt.Errorf("backup %s: %w", src.Name, err))
		}
	}

	// Phase 3: vault export (if requested).
	if params.Vault != nil {
		if err := exportVaultTo(ctx, params.Vault, target); err != nil {
			return failJob(ctx, params, fmt.Errorf("vault export: %w", err))
		}
	}

	// Phase 4: generate integrity manifest.
	manifest, err := GenerateManifest(ctx, target)
	if err != nil {
		return failJob(ctx, params, fmt.Errorf("generate manifest: %w", err))
	}
	if err := WriteManifest(ctx, manifest, target); err != nil {
		return failJob(ctx, params, fmt.Errorf("write manifest: %w", err))
	}

	// Phase 5: complete.
	completedAt := time.Now()
	job.Status = BackupStatusCompleted
	job.Progress = 1.0
	job.CompletedAt = &completedAt
	job.UpdatedAt = completedAt
	_ = params.Store.Update(ctx, job)

	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{
			Kind: eventbus.EventBackupCompleted,
			Data: BackupProgressData{
				JobID:       job.ID,
				Progress:    1.0,
				FilesCopied: job.FilesCopied,
				TotalFiles:  job.TotalFiles,
				BytesCopied: job.BytesCopied,
				TotalBytes:  job.TotalBytes,
			},
		})
	}

	return nil
}

func failJob(ctx context.Context, params SnapshotBackupParams, err error) error {
	now := time.Now()
	params.Job.Status = BackupStatusFailed
	params.Job.ErrorMsg = err.Error()
	params.Job.CompletedAt = &now
	params.Job.UpdatedAt = now
	// Best-effort: the returned error is already being reported to the caller.
	_ = params.Store.Update(ctx, params.Job)

	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{
			Kind: eventbus.EventBackupFailed,
			Data: BackupProgressData{JobID: params.Job.ID},
		})
	}
	return err
}

// scanTree counts the files under fsys and the bytes they hold.
func scanTree(ctx context.Context, fsys vfs.VFS) (files int, bytes int64, err error) {
	err = vfs.Walk(ctx, fsys, "", func(fi vfs.FileInfo) error {
		if !fi.IsDir {
			files++
			bytes += fi.Size
		}
		return nil
	})
	return
}

// exportVaultTo writes the vault export onto the target. SQLite writes the
// export and can only open it by a host path, so this is the one place the
// target's host directory is asked for.
func exportVaultTo(ctx context.Context, vault *VaultExportParams, target vfs.VFS) error {
	hp, ok := target.(vfs.HostPather)
	if !ok {
		return errors.New("target device has no host directory")
	}
	dir, err := hp.HostPath(ctx, "")
	if err != nil {
		return err
	}
	_, err = ExportVault(ctx, vault.Queries, vault.LiveKey, vault.RecoveryPassword, dir)
	return err
}

// deviceDirName produces a filesystem-safe directory name for a source device.
func deviceDirName(name, serial string) string {
	if serial == "" {
		return "internal"
	}
	suffix := serial
	if len(suffix) > 8 {
		suffix = suffix[:8]
	}
	safe := sanitizeName(name)
	if safe == "" {
		safe = "device"
	}
	return safe + "_" + suffix
}

func sanitizeName(name string) string {
	var b strings.Builder
	for _, r := range name {
		switch r {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|', 0:
			b.WriteRune('_')
		default:
			b.WriteRune(r)
		}
	}
	result := strings.TrimSpace(b.String())
	if len(result) > 200 {
		result = result[:200]
	}
	return result
}
