// cspell:ignore mmcblk nvme protectionutil sda vda

package protectionutil

import (
	"fmt"
	"path"
	"slices"
	"strings"
	"time"
)

// collectDrives joins snapshot-backup roles with devices and the newest
// completion for each serial. The result is ordered by serial.
func collectDrives(params StatusParams) []backupDrive {
	devices := make(map[string]Device, len(params.Devices))
	for _, device := range params.Devices {
		prev, ok := devices[device.Serial]
		if !ok || (prev.DevicePath == "" && device.DevicePath != "") {
			devices[device.Serial] = device
		}
	}

	completed := make(map[string]time.Time, len(params.Completions))
	for _, completion := range params.Completions {
		if completion.CompletedAt.IsZero() {
			continue
		}
		if prev, ok := completed[completion.Serial]; !ok || completion.CompletedAt.After(prev) {
			completed[completion.Serial] = completion.CompletedAt
		}
	}

	now := params.Now
	if now.IsZero() {
		now = time.Now()
	}

	seen := make(map[string]bool, len(params.Roles))
	drives := make([]backupDrive, 0)
	for _, role := range params.Roles {
		if role.Role != roleSnapshotBackup || seen[role.Serial] {
			continue
		}
		seen[role.Serial] = true
		device := devices[role.Serial]
		at, has := completed[role.Serial]
		// An empty serial is the internal drive. It can hold the role, and it
		// still does not count as a backup copy.
		internal := device.IsInternal || role.Serial == ""
		drive := backupDrive{
			serial:       role.Serial,
			name:         device.Name,
			internal:     internal,
			completedAt:  at,
			hasCompleted: has,
			diskKey:      groupKey(role.Serial, device.DevicePath),
			replaceSoon:  device.ReplaceSoon,
		}
		drive.qualifies = !internal && !device.ReplaceSoon && has && now.Sub(at) < StaleAfter
		drives = append(drives, drive)
	}
	slices.SortFunc(drives, func(a, b backupDrive) int {
		return strings.Compare(a.serial, b.serial)
	})
	return drives
}

// representatives maps each qualifying whole disk to the one drive that
// counts for it: the newest completion, then the lowest serial.
func representatives(drives []backupDrive) map[string]string {
	type best struct {
		serial string
		at     time.Time
	}
	chosen := make(map[string]best)
	for _, drive := range drives {
		if !drive.qualifies {
			continue
		}
		cur, ok := chosen[drive.diskKey]
		if !ok || drive.completedAt.After(cur.at) || (drive.completedAt.Equal(cur.at) && drive.serial < cur.serial) {
			chosen[drive.diskKey] = best{serial: drive.serial, at: drive.completedAt}
		}
	}
	reps := make(map[string]string, len(chosen))
	for key, winner := range chosen {
		reps[key] = winner.serial
	}
	return reps
}

// chooseNextStep picks the one recommendation. A drive that could become a
// new copy by finishing a backup asks for that. Otherwise the next copy has
// to be a drive that does not have the role yet. Two copies already in hand
// only need the keep-one-elsewhere tip.
func chooseNextStep(groups int, drives []backupDrive) NextStep {
	if groups >= 2 {
		return NextStepKeepElsewhere
	}
	counted := make(map[string]bool)
	for _, drive := range drives {
		if drive.qualifies {
			counted[drive.diskKey] = true
		}
	}
	for _, drive := range drives {
		if drive.internal || drive.qualifies || drive.replaceSoon || counted[drive.diskKey] {
			continue
		}
		return NextStepStartBackup
	}
	return NextStepAssignRole
}

func summarize(groups int, next NextStep) (Level, string) {
	copies := groups + 1
	level := LevelUnprotected
	switch {
	case groups >= 2:
		level = LevelProtected
	case groups == 1:
		level = LevelBasic
	}
	return level, sentence(copies, level, next)
}

func sentence(copies int, level Level, next NextStep) string {
	lead := fmt.Sprintf("Your files are on %d drives.", copies)
	if copies == 1 {
		lead = "Your files are only on this Quark."
	}
	var tail string
	switch next {
	case NextStepStartBackup:
		tail = "Start a backup onto your backup drive."
		if level == LevelBasic {
			tail = "Start a backup on your other backup drive."
		}
	case NextStepKeepElsewhere:
		tail = "Keep one backup drive somewhere else."
	default:
		tail = "Assign the backup role to another drive."
		if level == LevelBasic {
			tail = "Add a second backup drive and keep it somewhere else."
		}
	}
	return lead + " " + tail
}

func reportDrive(drive backupDrive, reps map[string]string) DriveStatus {
	status := DriveStatus{
		Serial: drive.serial,
		Name:   drive.name,
		Reason: reasonFor(drive, reps),
	}
	if drive.hasCompleted {
		at := drive.completedAt
		status.LastBackedUp = &at
	}
	status.Counts = status.Reason == ""
	return status
}

func reasonFor(drive backupDrive, reps map[string]string) string {
	if drive.internal {
		return ReasonInternal
	}
	if drive.replaceSoon {
		return ReasonReplaceSoon
	}
	if !drive.qualifies {
		if drive.hasCompleted {
			return ReasonStale
		}
		return ReasonNoCompletedBackup
	}
	if reps[drive.diskKey] != drive.serial {
		return ReasonSameDisk
	}
	return ""
}

// groupKey is the whole disk a drive belongs to. An empty device path gets a
// key nothing else shares, so an unplugged drive stands alone.
func groupKey(serial, devicePath string) string {
	if key := wholeDiskKey(devicePath); key != "" {
		return "disk:" + key
	}
	return "serial:" + serial
}

// wholeDiskKey is the physical disk a partition path names.
// /dev/disk3s5 and /dev/disk3s1 share disk3. /dev/sda1 and /dev/sda2 share sda.
// An empty path returns an empty key.
func wholeDiskKey(devicePath string) string {
	base := path.Base(devicePath)
	if devicePath == "" || base == "." || base == "/" {
		return ""
	}
	if key, ok := macDiskKey(base); ok {
		return key
	}
	if key, ok := prefixedPartitionKey(base, "nvme"); ok {
		return key
	}
	if key, ok := prefixedPartitionKey(base, "mmcblk"); ok {
		return key
	}
	if key, ok := letterDiskKey(base); ok {
		return key
	}
	return base
}

// macDiskKey matches disk3, disk3s5, and disk3s1s1. The number before the
// first "s" is the whole disk.
func macDiskKey(base string) (string, bool) {
	rest, ok := strings.CutPrefix(base, "disk")
	if !ok || rest == "" || rest[0] < '0' || rest[0] > '9' {
		return "", false
	}
	i := 0
	for i < len(rest) && rest[i] >= '0' && rest[i] <= '9' {
		i++
	}
	disk := "disk" + rest[:i]
	for i < len(rest) {
		if rest[i] != 's' {
			return "", false
		}
		j := i + 1
		for j < len(rest) && rest[j] >= '0' && rest[j] <= '9' {
			j++
		}
		if j == i+1 {
			return "", false
		}
		i = j
	}
	return disk, true
}

// prefixedPartitionKey matches nvme0n1p2 and mmcblk0p1. A trailing "p" plus
// digits is the partition; the rest is the whole disk.
func prefixedPartitionKey(base, prefix string) (string, bool) {
	if !strings.HasPrefix(base, prefix) {
		return "", false
	}
	if i := strings.LastIndex(base, "p"); i > len(prefix) && allDigits(base[i+1:]) {
		return base[:i], true
	}
	return base, true
}

// letterDiskKey matches sda1 and vda2. The trailing digits are the
// partition. A name that is already just the letters is the whole disk.
func letterDiskKey(base string) (string, bool) {
	i := 0
	for i < len(base) && base[i] >= 'a' && base[i] <= 'z' {
		i++
	}
	if i == 0 {
		return "", false
	}
	if i == len(base) {
		return base, true
	}
	if !allDigits(base[i:]) {
		return "", false
	}
	return base[:i], true
}

func allDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}
