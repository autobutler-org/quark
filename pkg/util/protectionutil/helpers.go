// cspell:ignore mmcblk nvme protectionutil sda vda

package protectionutil

import (
	"path"
	"slices"
	"strings"
	"time"
)

// collect joins roles, devices, and copies into data drives and backup
// drives, each ordered by serial.
func collect(params StatusParams) inputs {
	devices := make(map[string]Device, len(params.Devices))
	for _, device := range params.Devices {
		prev, ok := devices[device.Serial]
		if !ok || (prev.DevicePath == "" && device.DevicePath != "") {
			devices[device.Serial] = device
		}
	}

	in := inputs{
		copies:    make(map[string]map[string]time.Time),
		receiving: make(map[string]bool, len(params.Receiving)),
	}
	isBackup := make(map[string]bool)
	for _, role := range params.Roles {
		if role.Role != roleSnapshotBackup || isBackup[role.Serial] {
			continue
		}
		isBackup[role.Serial] = true
		device, connected := devices[role.Serial]
		name := device.Name
		if name == "" {
			name = role.Name
		}
		in.backups = append(in.backups, drive{
			serial:      role.Serial,
			name:        name,
			diskKey:     groupKey(role.Serial, device.DevicePath),
			connected:   connected,
			replaceSoon: device.ReplaceSoon,
		})
	}
	for serial, device := range devices {
		if isBackup[serial] {
			continue
		}
		in.data = append(in.data, drive{
			serial:    serial,
			name:      device.Name,
			diskKey:   groupKey(serial, device.DevicePath),
			connected: true,
		})
	}
	bySerial := func(a, b drive) int { return strings.Compare(a.serial, b.serial) }
	slices.SortFunc(in.backups, bySerial)
	slices.SortFunc(in.data, bySerial)

	for _, c := range params.Copies {
		if c.CopiedAt.IsZero() {
			continue
		}
		held := in.copies[c.BackupSerial]
		if held == nil {
			held = make(map[string]time.Time)
			in.copies[c.BackupSerial] = held
		}
		if prev, ok := held[c.SourceSerial]; !ok || c.CopiedAt.After(prev) {
			held[c.SourceSerial] = c.CopiedAt
		}
	}
	for _, serial := range params.Receiving {
		in.receiving[serial] = true
	}
	return in
}

// judgeDataDrive lists every backup drive's copy of data, says which count,
// and derives its level. Of two counting copies on one backup disk, the newer
// counts, then the lower serial.
func judgeDataDrive(data drive, in inputs, now time.Time) DataDrive {
	copies := make([]DataDriveCopy, 0)
	disks := make([]string, 0)
	for _, backup := range in.backups {
		at, ok := in.copies[backup.serial][data.serial]
		if !ok {
			continue
		}
		c := DataDriveCopy{BackupSerial: backup.serial, BackupName: backup.name, CopiedAt: at}
		switch {
		case backup.replaceSoon:
			c.Reason = ReasonReplaceSoon
		case backup.diskKey == data.diskKey:
			c.Reason = ReasonSameDisk
		case now.Sub(at) >= StaleAfter:
			c.Reason = ReasonStale
		}
		copies = append(copies, c)
		disks = append(disks, backup.diskKey)
	}

	counting := 0
	chosen := make(map[string]int)
	for i := range copies {
		if copies[i].Reason != "" {
			continue
		}
		j, ok := chosen[disks[i]]
		switch {
		case !ok:
			chosen[disks[i]] = i
			counting++
		case copies[i].CopiedAt.After(copies[j].CopiedAt):
			copies[j].Reason = ReasonDuplicateDisk
			chosen[disks[i]] = i
		default:
			copies[i].Reason = ReasonDuplicateDisk
		}
	}
	for i := range copies {
		copies[i].Counts = copies[i].Reason == ""
	}
	slices.SortStableFunc(copies, func(a, b DataDriveCopy) int { return b.CopiedAt.Compare(a.CopiedAt) })

	level := LevelUnprotected
	switch {
	case counting >= 2:
		level = LevelProtected
	case counting == 1:
		level = LevelBasic
	}
	return DataDrive{Serial: data.serial, Name: data.name, Level: level, Copies: copies}
}

// judgeBackupDrive lists the data drives backup holds a copy of and where it
// stands. The first state that applies wins.
func judgeBackupDrive(backup drive, in inputs, now time.Time) BackupDrive {
	held := in.copies[backup.serial]
	holds := make([]HeldCopy, 0)
	current := true
	for _, data := range in.data {
		at, ok := held[data.serial]
		if ok {
			holds = append(holds, HeldCopy{Serial: data.serial, Name: data.name, CopiedAt: at})
		}
		if data.diskKey != backup.diskKey && (!ok || now.Sub(at) >= StaleAfter) {
			current = false
		}
	}
	slices.SortStableFunc(holds, func(a, b HeldCopy) int { return b.CopiedAt.Compare(a.CopiedAt) })

	result := BackupDrive{Serial: backup.serial, Name: backup.name, Holds: holds}
	if len(holds) > 0 {
		newest := holds[0].CopiedAt
		result.NewestCopy = &newest
	}
	switch {
	case backup.replaceSoon:
		result.State = BackupStateRetired
	case in.receiving[backup.serial]:
		result.State = BackupStateReceiving
	case !backup.connected:
		result.State = BackupStateAway
	case len(held) == 0:
		result.State = BackupStateNoCopies
	case current:
		result.State = BackupStateCurrent
	default:
		result.State = BackupStateBehind
	}
	return result
}

// chooseNextStep picks the one recommendation from the weakest data drive's
// view. A backup drive that could add a counting copy of it asks for a
// backup. Otherwise the next copy needs a drive that does not have the role
// yet.
func chooseNextStep(weakest drive, judged DataDrive, in inputs) NextStep {
	if judged.Level == LevelProtected {
		return NextStepKeepElsewhere
	}
	counted := make(map[string]bool)
	for _, backup := range in.backups {
		for _, c := range judged.Copies {
			if c.Counts && c.BackupSerial == backup.serial {
				counted[backup.diskKey] = true
			}
		}
	}
	for _, backup := range in.backups {
		if !backup.replaceSoon && backup.diskKey != weakest.diskKey && !counted[backup.diskKey] {
			return NextStepStartBackup
		}
	}
	return NextStepAssignRole
}

// describe is one plain sentence about the whole Quark from its weakest data
// drive's view.
func describe(weakest DataDrive, next NextStep) string {
	switch weakest.Level {
	case LevelProtected:
		return "Every drive is on two backup drives. Keep one somewhere else."
	case LevelBasic:
		if next == NextStepStartBackup {
			return "Every drive has a copy on one backup drive. Back up onto your other backup drive."
		}
		return "Every drive has a copy on one backup drive. Add a second backup drive and keep it somewhere else."
	}
	lead := weakest.Name + " is only on this Quark."
	if len(weakest.Copies) > 0 {
		lead = weakest.Name + " has no recent backup."
	}
	if next == NextStepStartBackup {
		return lead + " Back up onto your backup drive."
	}
	return lead + " Assign the backup role to another drive."
}

// levelRank orders levels from weakest to strongest.
func levelRank(level Level) int {
	return map[Level]int{LevelBasic: 1, LevelProtected: 2}[level]
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
