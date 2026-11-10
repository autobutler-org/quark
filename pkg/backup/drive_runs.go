package backup

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"slices"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// The failures a caller of [ListDriveRuns] or [DeleteRun] can fix.
var (
	// ErrBackupRoleRequired reports a drive without the snapshot-backup
	// role: only the drives snapshots are written to hold runs.
	ErrBackupRoleRequired = errors.New("backups are kept only on a drive with the snapshot-backup role")
	// ErrDriveBusy reports a run that cannot be deleted yet: a backup onto
	// its drive may be linking from it, or a restore is reading it.
	ErrDriveBusy = errors.New("the drive is busy; delete the backup once it finishes")
)

// ListDriveRunsParams names the backup drive whose runs to list.
type ListDriveRunsParams struct {
	Ctx context.Context
	// Queries reads the drive's role, which must be snapshot-backup.
	Queries db.Querier
	// Registry holds the drive's files namespace.
	Registry vfs.Registry
	// DeviceSerial is the backup drive, "" for built-in storage.
	DeviceSerial string
}

// ListDriveRunsResult is a backup drive's complete runs.
type ListDriveRunsResult struct {
	// Runs is newest first, and empty, never nil, on a drive with none.
	Runs []Run `json:"runs"`
}

// ListDriveRuns lists the complete runs on a backup drive, newest first, as
// [ListRuns] does. A drive without the snapshot-backup role is
// [ErrBackupRoleRequired], and one that is not attached is the error
// [fileutil.FilesVFS] reports for it.
func ListDriveRuns(params ListDriveRunsParams) (ListDriveRunsResult, error) {
	fsys, err := backupDrive(params.Ctx, params.Queries, params.Registry, params.DeviceSerial)
	if err != nil {
		return ListDriveRunsResult{}, err
	}
	runs, err := ListRuns(params.Ctx, fsys)
	if err != nil {
		return ListDriveRunsResult{}, err
	}
	return ListDriveRunsResult{Runs: runs}, nil
}

// DeleteRunParams names the run to delete.
type DeleteRunParams struct {
	Ctx context.Context
	// Queries reads the drive's role and its active jobs, and holds the
	// drive's run cache.
	Queries db.Querier
	// Registry holds the drive's files namespace.
	Registry vfs.Registry
	// EventBus carries backup_deleted. Nil publishes nothing.
	EventBus *eventbus.Bus
	// DeviceSerial is the backup drive, "" for built-in storage.
	DeviceSerial string
	// Run is the run's folder under backups/, as [ListRuns] names it.
	Run string
}

// DeleteRunResult reports the run that was deleted.
type DeleteRunResult struct {
	Run Run `json:"run"`
}

// DeleteRun permanently deletes one complete run from a backup drive: its
// folder, through the drive's namespace, not into the trash. Every run is
// complete on its own, so no other run loses a file. Only a run [ListRuns]
// lists is deleted; any other name, a partial run or a path out of backups/
// included, is [ErrRunNotFound]. While a backup onto the drive is pending or
// running, or a restore reads the run, it is [ErrDriveBusy]. The drive's run
// cache is rewritten afterwards, so its protection status reads without the
// run, and backup_deleted is published.
func DeleteRun(params DeleteRunParams) (DeleteRunResult, error) {
	ctx := params.Ctx
	fsys, err := backupDrive(ctx, params.Queries, params.Registry, params.DeviceSerial)
	if err != nil {
		return DeleteRunResult{}, err
	}
	runs, err := ListRuns(ctx, fsys)
	if err != nil {
		return DeleteRunResult{}, err
	}
	i := slices.IndexFunc(runs, func(r Run) bool { return r.Folder == params.Run })
	if params.Run == "" || i < 0 {
		return DeleteRunResult{}, ErrRunNotFound
	}
	if backup := activeBackup(ctx, params.Queries, params.DeviceSerial); backup != nil {
		return DeleteRunResult{}, fmt.Errorf("%w: backup job %s is writing to it", ErrDriveBusy, backup.JobID)
	}
	if run, jobID := restoringRun(ctx, params.Queries, params.DeviceSerial); run == params.Run {
		return DeleteRunResult{}, fmt.Errorf("%w: restore job %d is reading this backup", ErrDriveBusy, jobID)
	}
	if err := removeRun(ctx, fsys, params.EventBus, params.DeviceSerial, params.Run); err != nil {
		return DeleteRunResult{}, err
	}
	// The run is gone either way; a stale cache is rewritten on the next
	// scan of the drive.
	if _, err := RefreshRunCache(ctx, params.Queries, params.DeviceSerial, fsys); err != nil {
		log.Printf("delete backup %s: %v", params.Run, err)
	}
	return DeleteRunResult{Run: runs[i]}, nil
}

// backupDrive is the files namespace of a drive holding the snapshot-backup
// role.
func backupDrive(ctx context.Context, queries db.Querier, registry vfs.Registry, serial string) (vfs.VFS, error) {
	if err := requireBackupRole(ctx, queries, serial); err != nil {
		return nil, err
	}
	return fileutil.FilesVFS(registry, serial)
}

// requireBackupRole is [ErrBackupRoleRequired] unless the drive holds the
// snapshot-backup role.
func requireBackupRole(ctx context.Context, queries db.Querier, serial string) error {
	role, err := queries.GetDeviceRole(ctx, serial)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && role != "snapshot-backup") {
		return ErrBackupRoleRequired
	}
	if err != nil {
		return fmt.Errorf("read the drive's role: %w", err)
	}
	return nil
}

// restoringRun is the run a pending or running restore from the drive reads,
// and that restore's job id, or "" when no restore reads from the drive.
func restoringRun(ctx context.Context, queries db.Querier, serial string) (string, int64) {
	row, err := queries.GetActiveRestoreJob(ctx, serial)
	if err != nil {
		return "", 0
	}
	var job RestoreJobParams
	if err := json.Unmarshal([]byte(row.Params), &job); err != nil {
		return "", 0
	}
	return job.Run, row.ID
}

// removeRun deletes a complete run's folder from fsys for good and publishes
// backup_deleted.
func removeRun(ctx context.Context, fsys vfs.VFS, bus *eventbus.Bus, serial, folder string) error {
	if err := fsys.Delete(ctx, runDir(folder), vfs.DeleteOptions{Recursive: true}); err != nil {
		return fmt.Errorf("delete backup %s: %w", folder, err)
	}
	if bus != nil {
		bus.Publish(eventbus.Event{
			Kind: eventbus.EventBackupDeleted,
			Data: eventbus.BackupDeleted{DeviceSerial: serial, Run: folder},
		})
	}
	return nil
}
