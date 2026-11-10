package backup

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"maps"
	"slices"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/deviceutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/util/jobutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ErrUnknownCadence reports a schedule whose cadence is not one of off,
// daily, weekly or monthly.
var ErrUnknownCadence = errors.New("cadence must be off, daily, weekly or monthly")

// scheduleKeyPrefix, followed by a backup drive's serial, is the settings row
// holding the drive's schedule as a JSON [schedule] (#3984). Built-in
// storage's serial is empty. A drive with no row, or one nobody can read, is
// off.
const scheduleKeyPrefix = "backupSchedule:"

// cadenceOff is the cadence of a drive that is backed up by hand only.
const cadenceOff = "off"

// cadences is how long each cadence but off lets a drive's newest copy age
// before a backup onto it is due.
var cadences = map[string]time.Duration{
	"daily":   24 * time.Hour,
	"weekly":  7 * 24 * time.Hour,
	"monthly": 30 * 24 * time.Hour,
}

// schedule is what a drive's settings row holds.
type schedule struct {
	Cadence string `json:"cadence"`
	// SourceSerials are the data drives to copy; empty is every data drive.
	SourceSerials []string `json:"sourceSerials"`
	// LastStartedAt is when the schedule last queued a backup, for
	// [scheduleRetryAfter]. Saving a schedule clears it.
	LastStartedAt time.Time `json:"lastStartedAt,omitzero"`
}

// scheduleRetryAfter is how long the schedule waits after queuing a backup
// before queuing another onto the same drive, or the cadence when that is
// shorter. A scheduled backup that failed leaves no run, so its drive stays
// due; this keeps the loop from queuing a failing backup every pass. Retry in
// Jobs still starts one at once.
const scheduleRetryAfter = 6 * time.Hour

// GetScheduleParams names the backup drive whose schedule to read.
type GetScheduleParams struct {
	Ctx context.Context
	// Queries reads the drive's role, its schedule, and its run cache.
	Queries db.Querier
	// Registry holds the drive's files namespace when it is attached.
	Registry vfs.Registry
	// DeviceSerial is the backup drive, "" for built-in storage.
	DeviceSerial string
}

// GetScheduleResult is a backup drive's schedule and whether a backup onto
// it is due.
type GetScheduleResult struct {
	DeviceSerial string `json:"deviceSerial"`
	// Cadence is off, daily, weekly or monthly.
	Cadence string `json:"cadence"`
	// SourceSerials are the data drives the schedule copies; empty, never
	// nil, is every data drive.
	SourceSerials []string `json:"sourceSerials"`
	// Due is true when the cadence is not off and the newest run holding a
	// scheduled source (any run, when every data drive is scheduled) is older
	// than the cadence, or there is none.
	Due bool `json:"due"`
	// WaitingForDrive is true when the backup is due and the drive is not
	// attached: it starts once the drive is plugged in.
	WaitingForDrive bool `json:"waitingForDrive"`
}

// GetSchedule reads a backup drive's schedule and works out whether a backup
// onto it is due, from its runs when it is attached and from its last scan
// when it is away. A drive without the snapshot-backup role is
// [ErrBackupRoleRequired].
func GetSchedule(params GetScheduleParams) (GetScheduleResult, error) {
	ctx := params.Ctx
	if err := requireBackupRole(ctx, params.Queries, params.DeviceSerial); err != nil {
		return GetScheduleResult{}, err
	}
	plan, err := readSchedule(ctx, params.Queries, params.DeviceSerial)
	if err != nil {
		return GetScheduleResult{}, err
	}
	copies, err := DriveCopies(ctx, params.Queries, params.Registry, params.DeviceSerial)
	if err != nil {
		return GetScheduleResult{}, err
	}
	due := isDue(plan, copies, time.Now())
	_, unmounted := fileutil.FilesVFS(params.Registry, params.DeviceSerial)
	return GetScheduleResult{
		DeviceSerial:    params.DeviceSerial,
		Cadence:         plan.Cadence,
		SourceSerials:   plan.SourceSerials,
		Due:             due,
		WaitingForDrive: due && unmounted != nil,
	}, nil
}

// SetScheduleParams sets a backup drive's schedule.
type SetScheduleParams struct {
	Ctx context.Context
	// Queries reads the device roles and holds the schedule.
	Queries db.Querier
	// Registry holds the drive's files namespace when it is attached.
	Registry vfs.Registry
	// Queue runs the backup a schedule makes due at once. Nil starts none.
	Queue *jobutil.Queue
	// Storage names the drives in the job name and reads the target's health.
	// Nil names them by serial and skips the health check.
	Storage *storageutil.StorageService
	// EventBus carries backup_schedule_changed. Nil publishes nothing.
	EventBus *eventbus.Bus
	// DeviceSerial is the backup drive, "" for built-in storage. It need not
	// be attached.
	DeviceSerial string
	// Cadence is off, daily, weekly or monthly; anything else is
	// [ErrUnknownCadence].
	Cadence string
	// SourceSerials are the data drives to copy; empty is every data drive.
	// One that is the drive itself or another backup drive is
	// [ErrSourceNotDataDrive]. One that is not attached is kept, and left out
	// of a run while it is away.
	SourceSerials []string
}

// SetScheduleResult is the schedule as saved, and the backup it started.
type SetScheduleResult struct {
	GetScheduleResult
	// JobID is the backup the schedule started because it was due and the
	// drive attached, or empty.
	JobID string `json:"jobId,omitempty"`
}

// SetSchedule saves a backup drive's schedule and publishes
// backup_schedule_changed. When a backup is now due and the drive is
// attached, it starts one the way [StartDueBackups] does. A drive without the
// snapshot-backup role is [ErrBackupRoleRequired].
func SetSchedule(params SetScheduleParams) (SetScheduleResult, error) {
	ctx := params.Ctx
	if err := requireBackupRole(ctx, params.Queries, params.DeviceSerial); err != nil {
		return SetScheduleResult{}, err
	}
	if _, ok := cadences[params.Cadence]; !ok && params.Cadence != cadenceOff {
		return SetScheduleResult{}, ErrUnknownCadence
	}
	backups, err := backupSerials(ctx, params.Queries)
	if err != nil {
		return SetScheduleResult{}, err
	}
	sources := slices.Compact(slices.Sorted(slices.Values(params.SourceSerials)))
	for _, serial := range sources {
		if serial == params.DeviceSerial || backups[serial] {
			return SetScheduleResult{}, fmt.Errorf("%s: %w", driveName(driveNames(params.Storage), serial), ErrSourceNotDataDrive)
		}
	}
	// LastStartedAt is left zero: an admin changing the schedule is a reason
	// to try again at once.
	if err := writeSchedule(ctx, params.Queries, params.DeviceSerial, schedule{Cadence: params.Cadence, SourceSerials: sources}); err != nil {
		return SetScheduleResult{}, err
	}
	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{
			Kind: eventbus.EventBackupScheduleChanged,
			Data: eventbus.BackupScheduleChanged{DeviceSerial: params.DeviceSerial},
		})
	}

	status, err := GetSchedule(GetScheduleParams{
		Ctx: ctx, Queries: params.Queries, Registry: params.Registry, DeviceSerial: params.DeviceSerial,
	})
	if err != nil {
		return SetScheduleResult{}, err
	}
	result := SetScheduleResult{GetScheduleResult: status}
	if params.Queue != nil {
		// The schedule is saved either way; the loop tries again later.
		jobID, err := startIfDue(StartDueBackupsParams{
			Ctx: ctx, Queries: params.Queries, Registry: params.Registry, Queue: params.Queue, Storage: params.Storage,
		}, params.DeviceSerial)
		if err != nil {
			log.Printf("backup schedule %q: %v", params.DeviceSerial, err)
		}
		result.JobID = jobID
	}
	return result, nil
}

// StartDueBackupsParams is what starting the due scheduled backups needs.
type StartDueBackupsParams struct {
	// Ctx bounds the checks made before each job is queued.
	Ctx context.Context
	// Queries reads the device roles, the schedules, and the run caches.
	Queries db.Querier
	// Registry holds the files namespaces of the attached drives.
	Registry vfs.Registry
	// Queue runs the backups.
	Queue *jobutil.Queue
	// Storage names the drives in the job name and reads each target's
	// health. Nil names them by serial and skips the health check.
	Storage *storageutil.StorageService
}

// StartDueBackupsResult reports the backups that were queued.
type StartDueBackupsResult struct {
	JobIDs []string
}

// StartDueBackups starts a backup onto every attached backup drive whose
// schedule is due, as the system (user 0), copying the schedule's sources
// that are still attached data drives. A drive that is away waits for its
// next turn, as does one with a backup already pending or running. A Replace
// soon drive is skipped: a schedule never stands in for the health
// acknowledgment a backup onto it needs. A failure on one drive is logged and
// the next is tried; only failing to list the drives is returned.
func StartDueBackups(params StartDueBackupsParams) (StartDueBackupsResult, error) {
	backups, err := backupSerials(params.Ctx, params.Queries)
	if err != nil {
		return StartDueBackupsResult{}, err
	}
	result := StartDueBackupsResult{JobIDs: []string{}}
	for _, serial := range slices.Sorted(maps.Keys(backups)) {
		jobID, err := startIfDue(params, serial)
		if err != nil {
			log.Printf("backup schedule %q: %v", serial, err)
		}
		if jobID != "" {
			result.JobIDs = append(result.JobIDs, jobID)
		}
	}
	return result, nil
}

// startIfDue starts the scheduled backup onto one backup drive when its
// schedule is due and it is attached, and returns the job's id. Every reason
// not to start one returns "" and, except a backup already running, is
// logged or returned.
func startIfDue(params StartDueBackupsParams, serial string) (string, error) {
	ctx := params.Ctx
	plan, err := readSchedule(ctx, params.Queries, serial)
	if err != nil || plan.Cadence == cadenceOff {
		return "", err
	}
	if _, err := fileutil.FilesVFS(params.Registry, serial); err != nil {
		return "", nil
	}
	copies, err := DriveCopies(ctx, params.Queries, params.Registry, serial)
	if err != nil || !isDue(plan, copies, time.Now()) {
		return "", err
	}
	if time.Since(plan.LastStartedAt) < min(cadences[plan.Cadence], scheduleRetryAfter) {
		return "", nil
	}
	if err := deviceutil.RefuseReplaceSoonTarget(deviceutil.BackupHealthParams{
		Ctx: ctx, Storage: params.Storage, Serial: serial,
	}); err != nil {
		return "", fmt.Errorf("not starting the scheduled backup: %w", err)
	}

	sources := plan.SourceSerials
	if len(sources) > 0 {
		backups, err := backupSerials(ctx, params.Queries)
		if err != nil {
			return "", err
		}
		sources = slices.DeleteFunc(slices.Clone(sources), func(s string) bool {
			_, err := fileutil.FilesVFS(params.Registry, s)
			return err != nil || s == serial || backups[s]
		})
		if len(sources) == 0 {
			log.Printf("backup schedule %q: none of its sources %q is an attached data drive; waiting", serial, plan.SourceSerials)
			return "", nil
		}
	}
	started, err := StartSnapshotBackup(StartSnapshotBackupParams{
		Ctx:                ctx,
		Queries:            params.Queries,
		Registry:           params.Registry,
		Queue:              params.Queue,
		TargetDeviceSerial: serial,
		SourceSerials:      sources,
		Storage:            params.Storage,
	})
	var inProgress *BackupInProgressError
	if errors.As(err, &inProgress) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	plan.LastStartedAt = time.Now()
	if err := writeSchedule(ctx, params.Queries, serial, plan); err != nil {
		log.Printf("backup schedule %q: %v", serial, err)
	}
	return started.JobID, nil
}

// writeSchedule saves a drive's schedule row.
func writeSchedule(ctx context.Context, queries db.Querier, serial string, plan schedule) error {
	value, err := json.Marshal(plan)
	if err != nil {
		return err
	}
	if err := queries.SetSetting(ctx, db.SetSettingParams{Key: scheduleKeyPrefix + serial, Value: string(value)}); err != nil {
		return fmt.Errorf("save the schedule of drive %q: %w", serial, err)
	}
	return nil
}

// isDue reports whether a backup under plan is due at now, given the copies
// the drive holds: the newest copy of a scheduled source (of any drive, when
// every data drive is scheduled) is older than the cadence, or there is none.
// It reads the newest run holding any scheduled source rather than all of
// them, so a source that is away for good does not make the drive due again
// after every run.
func isDue(plan schedule, copies []RunCopy, now time.Time) bool {
	cadence, ok := cadences[plan.Cadence]
	if !ok {
		return false
	}
	var last time.Time
	for _, c := range copies {
		if (len(plan.SourceSerials) == 0 || slices.Contains(plan.SourceSerials, c.Serial)) && c.CompletedAt.After(last) {
			last = c.CompletedAt
		}
	}
	return last.IsZero() || now.Sub(last) >= cadence
}

// readSchedule reads a drive's schedule. A drive with no row, a row nobody
// can read, or an unknown cadence is off.
func readSchedule(ctx context.Context, queries db.Querier, serial string) (schedule, error) {
	off := schedule{Cadence: cadenceOff, SourceSerials: []string{}}
	value, err := queries.GetSetting(ctx, scheduleKeyPrefix+serial)
	if errors.Is(err, sql.ErrNoRows) {
		return off, nil
	}
	if err != nil {
		return schedule{}, fmt.Errorf("read the schedule of drive %q: %w", serial, err)
	}
	var plan schedule
	if err := json.Unmarshal([]byte(value), &plan); err != nil {
		return off, nil
	}
	if _, ok := cadences[plan.Cadence]; !ok {
		plan.Cadence = cadenceOff
	}
	if plan.SourceSerials == nil {
		plan.SourceSerials = []string{}
	}
	return plan, nil
}
