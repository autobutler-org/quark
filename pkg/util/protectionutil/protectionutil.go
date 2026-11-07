// cspell:ignore protectionutil

// Package protectionutil derives how protected a Quark's files are.
//
// Copy 1 is the live data on the default-storage drive and never counts as a
// backup. A drive counts when its role is snapshot-backup, it is not the
// internal drive, its health is not Replace soon, and one of its completed
// snapshot-backup jobs finished inside [StaleAfter]. A failed job, a job that
// has not completed, a completion older than StaleAfter, and a Replace soon
// drive do not count. Watch and Unknown still follow the 30-day rule. Two
// partitions of one physical disk count once. An empty device path is not
// grouped with any other drive. Offsite is not tracked.
//
// [Status] does not open the database or the filesystem. The caller passes
// the roles, devices, and completed-job timestamps it has already loaded.
package protectionutil

import "time"

// StaleAfter is how old a completed snapshot backup may be and still count.
// It is the same 30-day window docs/architecture/backup.md uses for backup_stale.
const StaleAfter = 30 * 24 * time.Hour

// Level is how protected the files are.
type Level string

const (
	// LevelUnprotected means no snapshot-backup drive has a completed backup inside StaleAfter.
	LevelUnprotected Level = "unprotected"
	// LevelBasic means exactly one such drive, after partitions of one disk are grouped.
	LevelBasic Level = "basic"
	// LevelProtected means two or more such drives.
	LevelProtected Level = "protected"
)

// NextStep is the one action the status recommends.
type NextStep string

const (
	// NextStepAssignRole means give the snapshot-backup role to another drive.
	NextStepAssignRole NextStep = "assign-backup-role"
	// NextStepStartBackup means a snapshot-backup drive still needs a completed backup inside StaleAfter.
	NextStepStartBackup NextStep = "start-backup"
	// NextStepKeepElsewhere means two backup copies exist; keep one of those drives somewhere else.
	NextStepKeepElsewhere NextStep = "keep-one-elsewhere"
)

const (
	// ReasonInternal is why the internal drive does not count.
	ReasonInternal = "The internal drive is not a backup copy."
	// ReasonNoCompletedBackup is why a snapshot-backup drive with no completed job does not count.
	// A failed or unfinished job leaves this reason.
	ReasonNoCompletedBackup = "No completed backup yet."
	// ReasonStale is why a completion outside StaleAfter does not count.
	ReasonStale = "The last backup is more than 30 days old."
	// ReasonSameDisk is why a second partition of a disk that already counts does not count.
	ReasonSameDisk = "This partition is on the same disk as another backup."
	// ReasonReplaceSoon is why a drive whose health verdict is Replace soon does not count.
	ReasonReplaceSoon = "This drive should be replaced soon, so it does not count as a backup copy."
)

// Role is the role assigned to one device. Serial is empty for the internal drive.
type Role struct {
	Serial string
	Role   string
}

// Device is one detected device. DevicePath is the partition path, such as
// /dev/disk3s5 or /dev/sda1. An empty DevicePath stands alone.
type Device struct {
	Serial     string
	Name       string
	DevicePath string
	IsInternal bool
	// ReplaceSoon is true when the drive's health verdict is replace soon.
	// The drive does not count as a backup copy. Watch and Unknown leave this
	// false and still follow the 30-day rule.
	ReplaceSoon bool
}

// Completion is one completed snapshot-backup job, or a drive's own record of
// its last completed snapshot. Failed and unfinished jobs are not completions.
type Completion struct {
	Serial      string
	CompletedAt time.Time
}

// StatusParams is everything [Status] needs. The caller has already loaded it.
type StatusParams struct {
	// Now is the time staleness is judged against. The zero time means time.Now.
	Now time.Time
	// Roles are the device roles, including default-storage and unassigned.
	Roles []Role
	// Devices are the detected devices, internal included. A role whose serial
	// is missing here is an unplugged drive: it has no path and stands alone.
	Devices []Device
	// Completions are completed snapshot-backup jobs and per-drive records. The newest time per
	// serial is the one that counts.
	Completions []Completion
}

// DriveStatus is one snapshot-backup drive in the response.
type DriveStatus struct {
	Serial string `json:"serial"`
	Name   string `json:"name,omitempty"`
	// Counts is whether this drive adds a backup copy. Partitions of one disk
	// share a single count.
	Counts bool `json:"counts"`
	// Reason is why Counts is false. Empty when Counts is true.
	Reason string `json:"reason"`
	// LastBackedUp is when this drive's newest completed snapshot backup
	// finished. It is nil when the drive has no completed backup.
	LastBackedUp *time.Time `json:"lastBackedUp"`
}

// StatusResult is how protected the files are, and what to do next.
type StatusResult struct {
	Level    Level         `json:"level" enums:"unprotected,basic,protected"`
	Sentence string        `json:"sentence"`
	NextStep NextStep      `json:"nextStep" enums:"assign-backup-role,start-backup,keep-one-elsewhere"`
	Drives   []DriveStatus `json:"drives"`
}

// Status derives the protection level from roles, devices, and completed
// snapshot-backup jobs. It does not open the database or the filesystem.
func Status(params StatusParams) StatusResult {
	drives := collectDrives(params)
	reps := representatives(drives)
	next := chooseNextStep(len(reps), drives)
	level, sentence := summarize(len(reps), next)
	reports := make([]DriveStatus, 0, len(drives))
	for _, drive := range drives {
		reports = append(reports, reportDrive(drive, reps))
	}
	return StatusResult{
		Level:    level,
		Sentence: sentence,
		NextStep: next,
		Drives:   reports,
	}
}
