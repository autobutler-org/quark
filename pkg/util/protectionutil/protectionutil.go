// cspell:ignore protectionutil

// Package protectionutil derives how protected a Quark's files are.
//
// Drives come in two kinds. A data drive is every connected device whose role
// is not snapshot-backup: built-in storage, the default-storage drive, and
// unassigned drives. Its files are what needs protecting. A backup drive is
// every snapshot-backup role, connected or not. A snapshot copies every data
// drive onto one backup drive as a run folder under backups/, whose manifest
// names the data drives it holds and when it completed. A backup drive's copy
// of a data drive is its newest run naming that drive. The run folders are
// the truth: an attached drive is scanned on every read, and a drive that is
// away answers from the scan cached when it was last attached.
//
// A backup drive's copy of a data drive counts when the backup drive is not
// Replace soon, the copy finished inside [StaleAfter], and the two are on
// different physical disks. A copy on built-in storage protects a USB
// main-storage drive and never built-in storage's own files. Two partitions of
// one backup disk count once per data drive. An empty device path is not
// grouped with any other drive. The live mirror onto the default-storage
// drive is not a copy. Offsite is not tracked.
//
// A data drive with no counting copy is unprotected, one is basic, and two or
// more is protected. The whole Quark is as protected as its weakest data drive.
//
// [Status] does not open the database or the filesystem. The caller passes
// the roles, devices, copies, and active backup targets it has already
// loaded.
package protectionutil

import "time"

// StaleAfter is how old a copy may be and still count. It is the same 30-day
// window docs/architecture/backup.md uses for backup_stale.
const StaleAfter = 30 * 24 * time.Hour

// Level is how protected the files are.
type Level string

const (
	// LevelUnprotected means no counting copy.
	LevelUnprotected Level = "unprotected"
	// LevelBasic means exactly one counting copy, after partitions of one disk are grouped.
	LevelBasic Level = "basic"
	// LevelProtected means two or more counting copies.
	LevelProtected Level = "protected"
)

// NextStep is the one action the status recommends.
type NextStep string

const (
	// NextStepAssignRole means give the snapshot-backup role to another drive:
	// no backup drive can give the weakest data drive another counting copy.
	NextStepAssignRole NextStep = "assign-backup-role"
	// NextStepStartBackup means a backup drive could give the weakest data
	// drive another counting copy by backing up onto it.
	NextStepStartBackup NextStep = "start-backup"
	// NextStepKeepElsewhere means every data drive is protected; keep one backup drive somewhere else.
	NextStepKeepElsewhere NextStep = "keep-one-elsewhere"
)

// BackupState is where one backup drive stands.
type BackupState string

const (
	// BackupStateRetired means its health verdict is Replace soon, so none of its copies count.
	BackupStateRetired BackupState = "retired"
	// BackupStateReceiving means a snapshot backup onto it is pending or running.
	BackupStateReceiving BackupState = "receiving"
	// BackupStateAway means it holds the role and is not connected. Its copies still count.
	BackupStateAway BackupState = "away"
	// BackupStateNoCopies means it holds no copy of any drive yet.
	BackupStateNoCopies BackupState = "no-copies"
	// BackupStateCurrent means it holds a copy inside StaleAfter of every data drive on another disk.
	BackupStateCurrent BackupState = "current"
	// BackupStateBehind means a data drive's copy is missing or older than StaleAfter.
	BackupStateBehind BackupState = "behind"
)

const (
	// ReasonStale is why a copy older than StaleAfter does not count.
	ReasonStale = "This copy is more than 30 days old."
	// ReasonSameDisk is why a copy on the same physical disk as its data drive does not count.
	ReasonSameDisk = "This copy is on the same disk as the drive."
	// ReasonDuplicateDisk is why a second partition of a backup disk that already counts does not count.
	ReasonDuplicateDisk = "This copy is on the same disk as another copy of the drive."
	// ReasonReplaceSoon is why a copy on a drive whose health verdict is Replace soon does not count.
	ReasonReplaceSoon = "The drive holding this copy should be replaced soon, so the copy does not count."
)

// Role is the role assigned to one device. Serial is empty for the internal
// drive. Name is what to call the drive when it is not connected.
type Role struct {
	Serial string
	Role   string
	Name   string
}

// Device is one connected device. DevicePath is the partition path, such as
// /dev/disk3s5 or /dev/sda1. An empty DevicePath stands alone.
type Device struct {
	Serial     string
	Name       string
	DevicePath string
	// ReplaceSoon is true when the drive's health verdict is replace soon. Its
	// copies do not count. Watch and Unknown leave this false and still
	// follow the 30-day rule.
	ReplaceSoon bool
}

// Copy is a backup drive's copy of one data drive: a run on the backup drive
// naming the data drive, dated when the run completed. The newest per pair is
// the one that counts.
type Copy struct {
	BackupSerial string
	SourceSerial string
	CopiedAt     time.Time
}

// StatusParams is everything [Status] needs. The caller has already loaded it.
type StatusParams struct {
	// Now is the time staleness is judged against. The zero time means time.Now.
	Now time.Time
	// Roles are the device roles, including default-storage and unassigned.
	Roles []Role
	// Devices are the connected devices, internal included. A role whose
	// serial is missing here is an unplugged drive: it has no path and stands
	// alone.
	Devices []Device
	// Copies are the copies the backup drives' runs hold.
	Copies []Copy
	// Receiving are the backup drives a snapshot backup is pending or running onto.
	Receiving []string
}

// DataDriveCopy is one backup drive's copy of a data drive.
type DataDriveCopy struct {
	BackupSerial string    `json:"backupSerial"`
	BackupName   string    `json:"backupName"`
	CopiedAt     time.Time `json:"copiedAt"`
	// Counts is whether this copy protects the drive.
	Counts bool `json:"counts"`
	// Reason is why Counts is false. Empty when Counts is true.
	Reason string `json:"reason"`
}

// DataDrive is one drive holding files, and the copies of it.
type DataDrive struct {
	// Serial is empty for built-in storage.
	Serial string `json:"serial"`
	Name   string `json:"name"`
	Level  Level  `json:"level" enums:"unprotected,basic,protected"`
	// Copies is one per backup drive with a copy of this drive, newest first.
	Copies []DataDriveCopy `json:"copies"`
}

// HeldCopy is one data drive a backup drive holds a copy of.
type HeldCopy struct {
	Serial   string    `json:"serial"`
	Name     string    `json:"name"`
	CopiedAt time.Time `json:"copiedAt"`
}

// BackupDrive is one snapshot-backup drive and what it holds.
type BackupDrive struct {
	Serial string      `json:"serial"`
	Name   string      `json:"name"`
	State  BackupState `json:"state" enums:"no-copies,receiving,current,behind,away,retired"`
	// Holds is one per current data drive this drive has a copy of, newest first.
	Holds []HeldCopy `json:"holds"`
	// NewestCopy is the newest of Holds. Nil when Holds is empty.
	NewestCopy *time.Time `json:"newestCopy"`
}

// StatusResult is how protected the files are, and what to do next.
type StatusResult struct {
	// Level is the weakest data drive's. Unprotected when there is none.
	Level    Level    `json:"level" enums:"unprotected,basic,protected"`
	Sentence string   `json:"sentence"`
	NextStep NextStep `json:"nextStep" enums:"assign-backup-role,start-backup,keep-one-elsewhere"`
	// DataDrives is ordered by serial, so built-in storage comes first.
	DataDrives []DataDrive `json:"dataDrives"`
	// BackupDrives is ordered by serial.
	BackupDrives []BackupDrive `json:"backupDrives"`
}

// Status derives the protection level from roles, devices, and copies.
// It does not open the database or the filesystem.
func Status(params StatusParams) StatusResult {
	now := params.Now
	if now.IsZero() {
		now = time.Now()
	}
	in := collect(params)

	dataDrives := make([]DataDrive, 0, len(in.data))
	for _, data := range in.data {
		dataDrives = append(dataDrives, judgeDataDrive(data, in, now))
	}
	backupDrives := make([]BackupDrive, 0, len(in.backups))
	for _, backup := range in.backups {
		backupDrives = append(backupDrives, judgeBackupDrive(backup, in, now))
	}

	weakest := -1
	for i, data := range dataDrives {
		if weakest < 0 || levelRank(data.Level) < levelRank(dataDrives[weakest].Level) {
			weakest = i
		}
	}
	level := LevelUnprotected
	next := NextStepAssignRole
	sentence := "No drive holds files to back up. Assign the backup role to another drive."
	if weakest >= 0 {
		level = dataDrives[weakest].Level
		next = chooseNextStep(in.data[weakest], dataDrives[weakest], in)
		sentence = describe(dataDrives[weakest], next)
	}
	return StatusResult{
		Level:        level,
		Sentence:     sentence,
		NextStep:     next,
		DataDrives:   dataDrives,
		BackupDrives: backupDrives,
	}
}
