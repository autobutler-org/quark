package backup

import (
	"context"
	"errors"
	"fmt"
	"log"
	"path"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// SnapshotBackup copies every source onto target as a new run: a folder
// under backups/ named after the minute it started, holding one folder per
// source drive, the chat and vault exports, and the manifest (#4032). The run
// is written under backups/.<run>.partial/ and renamed once it is complete,
// so nothing that reads runs ever sees half of one, and a run that fails or
// is canceled removes its partial folder. A file unchanged since the
// previous complete run is hard-linked from it where the drive can link, so
// each run is complete on its own without taking the space twice.
func SnapshotBackup(
	ctx context.Context,
	params SnapshotBackupParams,
	sources []SourceDevice,
	target vfs.VFS,
) error {
	job := params.Job
	now := time.Now()

	job.SourceNames = make([]string, len(sources))
	for i, src := range sources {
		job.SourceNames[i] = sourceName(src)
	}

	job.Status = BackupStatusScanning
	job.UpdatedAt = now
	params.save()

	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{
			Kind: eventbus.EventBackupStarted,
			Data: BackupProgressData{JobID: job.ID},
		})
	}

	removeStalePartials(ctx, target)
	folder, err := newRunFolder(ctx, target, now)
	if err != nil {
		return failJob(params, fmt.Errorf("name the run: %w", err))
	}
	partial := partialDir(folder)
	if err := target.MkdirAll(ctx, partial); err != nil {
		return failJob(params, fmt.Errorf("create %s: %w", partial, err))
	}
	completedAt, err := writeRun(ctx, params, sources, target, folder)
	if err != nil {
		// On a context of its own, so a canceled run is cleaned up too.
		if rmErr := target.Delete(context.WithoutCancel(ctx), partial, vfs.DeleteOptions{Recursive: true}); rmErr != nil {
			log.Printf("snapshot backup: remove %s: %v", partial, rmErr)
		}
		return failJob(params, err)
	}

	// Phase 5: complete.
	job.Status = BackupStatusCompleted
	job.CurrentSource = ""
	job.Progress = 1.0
	job.CompletedAt = &completedAt
	job.UpdatedAt = completedAt
	params.save()

	// Recorded before the event, so a client that asks again on it sees the
	// new time. The backup itself succeeded, so a failed record is only logged.
	// The target's run cache is rewritten so the new run counts while the
	// drive is away.
	if params.Queries != nil {
		_, cacheErr := RefreshRunCache(ctx, params.Queries, params.TargetDeviceSerial, target)
		if err := errors.Join(
			RecordSnapshot(ctx, params.Queries, completedAt),
			RecordDriveSnapshot(ctx, params.Queries, params.TargetDeviceSerial, completedAt),
			cacheErr,
		); err != nil {
			log.Printf("snapshot backup: %v", err)
		}
	}

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

// writeRun fills the run's partial folder, then renames it to the run's
// folder, and returns when the run completed.
func writeRun(
	ctx context.Context,
	params SnapshotBackupParams,
	sources []SourceDevice,
	target vfs.VFS,
	folder string,
) (time.Time, error) {
	job := params.Job
	partial := partialDir(folder)

	// Where each source drive's files sit in the previous complete run.
	runs, err := ListRuns(ctx, target)
	if err != nil {
		return time.Time{}, err
	}
	previous := map[string]string{}
	if len(runs) > 0 {
		for _, d := range runs[0].Drives {
			previous[d.Serial] = path.Join(runDir(runs[0].Folder), d.Folder)
		}
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
			return time.Time{}, fmt.Errorf("scan %s: %w", src.Name, err)
		}
		sdp.FilesTotal = files
		sdp.BytesTotal = bytes
		job.TotalFiles += files
		job.TotalBytes += bytes
		job.SourceDevices[i] = sdp
	}
	job.UpdatedAt = time.Now()
	params.save()

	// Phase 2: copy files from each source to the target.
	job.Status = BackupStatusCopying
	job.UpdatedAt = time.Now()
	params.save()

	drives := make([]ManifestDrive, 0, len(sources))
	lastPublish := time.Time{}
	for i, src := range sources {
		driveFolder := driveDirName(src.Name, src.Serial)
		drives = append(drives, ManifestDrive{Folder: driveFolder, Serial: src.Serial, Name: src.Name})
		targetBase := path.Join(partial, driveFolder)
		if err := target.MkdirAll(ctx, targetBase); err != nil {
			return time.Time{}, fmt.Errorf("create %s: %w", targetBase, err)
		}
		job.CurrentSource = job.SourceNames[i]
		prevBase, hasPrevious := previous[src.Serial]

		err := vfs.Walk(ctx, src.Files, "", func(srcInfo vfs.FileInfo) error {
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := skipBackupsDir(srcInfo); err != nil {
				return err
			}

			relPath := srcInfo.Path
			targetPath := path.Join(targetBase, relPath)

			if srcInfo.IsDir {
				return target.MkdirAll(ctx, targetPath)
			}

			// Unchanged since the previous run: linked from there, not copied.
			if hasPrevious && linkUnchanged(ctx, target, path.Join(prevBase, relPath), targetPath, srcInfo) {
				job.FilesSkipped++
				job.SourceDevices[i].FilesSkipped++
				return nil
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
			params.save()

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
			return time.Time{}, fmt.Errorf("backup %s: %w", src.Name, err)
		}
	}

	// Phase 3: the chat and vault exports. They are ciphertext and need no
	// password, so every snapshot of a SQLite-backed Quark carries both. On
	// PostgreSQL the database's own backups carry them, and the run is the
	// files and the manifest.
	if params.LiveDB != nil {
		if err := exportCiphertextTo(ctx, params, target, partial); err != nil {
			return time.Time{}, err
		}
	}

	// Phase 4: generate integrity manifest, then put the run in place.
	manifest, err := GenerateManifest(ctx, target, partial)
	if err != nil {
		return time.Time{}, fmt.Errorf("generate manifest: %w", err)
	}
	completedAt := time.Now()
	manifest.CompletedAt = completedAt
	manifest.Drives = drives
	if err := WriteManifest(ctx, manifest, target, partial); err != nil {
		return time.Time{}, fmt.Errorf("write manifest: %w", err)
	}
	if err := target.Move(ctx, partial, runDir(folder)); err != nil {
		return time.Time{}, fmt.Errorf("complete the run: %w", err)
	}
	return completedAt, nil
}

// linkUnchanged hard-links dst to prev, the file's copy in the previous run,
// when the source has not changed since: the same size, and not newer than
// that copy. It reports false, and the caller copies, when there is no such
// copy, the file changed, or the drive cannot link: FAT, exFAT, or a
// namespace with no [vfs.Linker]. Both paths are on the backup drive.
func linkUnchanged(ctx context.Context, target vfs.VFS, prev, dst string, src vfs.FileInfo) bool {
	linker, ok := target.(vfs.Linker)
	if !ok {
		return false
	}
	info, err := target.Stat(ctx, prev)
	if err != nil || info.IsDir || info.Size != src.Size || info.ModTime.Before(src.ModTime) {
		return false
	}
	return linker.Link(ctx, prev, dst) == nil
}

func (p SnapshotBackupParams) save() {
	if p.Save != nil {
		p.Save(p.Job)
	}
}

func failJob(params SnapshotBackupParams, err error) error {
	now := time.Now()
	params.Job.Status = BackupStatusFailed
	params.Job.ErrorMsg = err.Error()
	params.Job.CompletedAt = &now
	params.Job.UpdatedAt = now
	params.save()

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
		if err := skipBackupsDir(fi); err != nil {
			return err
		}
		if !fi.IsDir {
			files++
			bytes += fi.Size
		}
		return nil
	})
	return
}

// exportCiphertextTo writes the chat and vault exports into dir on the
// target, each bound to this Quark by a MAC beside it (#4010). On PostgreSQL
// it writes neither: the database's own backups carry both.
func exportCiphertextTo(ctx context.Context, params SnapshotBackupParams, target vfs.VFS, dir string) error {
	if db.BackendOf(params.LiveDB) == db.Postgres {
		return nil
	}
	hostPath, err := hostDir(ctx, target, dir)
	if err != nil {
		return err
	}
	// No Queries is a snapshot nothing records, in tests: it writes unbound.
	var key []byte
	if params.Queries != nil {
		if key, err = bindingKey(ctx, params.Queries); err != nil {
			return err
		}
		if err := markDriveBound(ctx, params.Queries, params.TargetDeviceSerial); err != nil {
			return err
		}
	}
	for _, b := range ciphertextBackups {
		if _, err := b.export(ctx, params.LiveDB, hostPath, key); err != nil {
			return fmt.Errorf("export %s: %w", b.filename, err)
		}
	}
	return nil
}

// hostDir is the host directory of dir on fsys. SQLite writes the chat and
// vault exports and can only open them by a host path, so they are the one
// reason a backup drive's host directory is asked for.
func hostDir(ctx context.Context, fsys vfs.VFS, dir string) (string, error) {
	hp, ok := fsys.(vfs.HostPather)
	if !ok {
		return "", errors.New("target device has no host directory")
	}
	return hp.HostPath(ctx, dir)
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
