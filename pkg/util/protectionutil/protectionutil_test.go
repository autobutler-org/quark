// cspell:ignore mmcblk protectionutil sda sdb sdc sdd

package protectionutil_test

import (
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/protectionutil"
)

var testNow = time.Date(2026, 4, 1, 12, 0, 0, 0, time.UTC)

// builtIn is the internal drive, a data drive unless it takes the backup role.
var builtIn = protectionutil.Device{Serial: "", Name: "Built-in storage", DevicePath: "/dev/mmcblk0p2"}

func backupRole(serial string) protectionutil.Role {
	return protectionutil.Role{Serial: serial, Role: "snapshot-backup"}
}

func copyOf(backup, source string, at time.Time) protectionutil.Copy {
	return protectionutil.Copy{BackupSerial: backup, SourceSerial: source, CopiedAt: at}
}

func dataDrive(t *testing.T, got protectionutil.StatusResult, serial string) protectionutil.DataDrive {
	t.Helper()
	for _, drive := range got.DataDrives {
		if drive.Serial == serial {
			return drive
		}
	}
	t.Fatalf("no data drive %q in %+v", serial, got.DataDrives)
	return protectionutil.DataDrive{}
}

func backupDrive(t *testing.T, got protectionutil.StatusResult, serial string) protectionutil.BackupDrive {
	t.Helper()
	for _, drive := range got.BackupDrives {
		if drive.Serial == serial {
			return drive
		}
	}
	t.Fatalf("no backup drive %q in %+v", serial, got.BackupDrives)
	return protectionutil.BackupDrive{}
}

func TestStatus_NoBackupDrive(t *testing.T) {
	got := protectionutil.Status(protectionutil.StatusParams{
		Now:     testNow,
		Roles:   []protectionutil.Role{{Serial: "", Role: "default-storage"}},
		Devices: []protectionutil.Device{builtIn},
	})
	if got.Level != protectionutil.LevelUnprotected || got.NextStep != protectionutil.NextStepAssignRole {
		t.Fatalf("status = %+v, want unprotected and assign-backup-role", got)
	}
	const want = "Built-in storage is only on this Quark. Assign the backup role to another drive."
	if got.Sentence != want {
		t.Errorf("sentence = %q, want %q", got.Sentence, want)
	}
	if len(got.DataDrives) != 1 || got.DataDrives[0].Level != protectionutil.LevelUnprotected {
		t.Fatalf("data drives = %+v, want built-in storage unprotected", got.DataDrives)
	}
	if got.DataDrives[0].Copies == nil || len(got.DataDrives[0].Copies) != 0 {
		t.Errorf("copies = %#v, want an empty list", got.DataDrives[0].Copies)
	}
	if got.BackupDrives == nil || len(got.BackupDrives) != 0 {
		t.Errorf("backup drives = %#v, want an empty list", got.BackupDrives)
	}
}

func TestStatus_OneFreshCopyIsBasic(t *testing.T) {
	fresh := testNow.Add(-protectionutil.StaleAfter + time.Second)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now:   testNow,
		Roles: []protectionutil.Role{{Serial: "", Role: "default-storage"}, backupRole("usb-a")},
		Devices: []protectionutil.Device{
			builtIn,
			{Serial: "usb-a", Name: "Backup A", DevicePath: "/dev/sdb1"},
		},
		Copies: []protectionutil.Copy{
			copyOf("usb-a", "", testNow.Add(-protectionutil.StaleAfter-time.Hour)),
			copyOf("usb-a", "", fresh),
		},
	})
	if got.Level != protectionutil.LevelBasic || got.NextStep != protectionutil.NextStepAssignRole {
		t.Fatalf("status = %+v, want basic and assign-backup-role", got)
	}
	const want = "Every drive has a copy on one backup drive. Add a second backup drive and keep it somewhere else."
	if got.Sentence != want {
		t.Errorf("sentence = %q, want %q", got.Sentence, want)
	}
	data := dataDrive(t, got, "")
	if data.Name != "Built-in storage" || data.Level != protectionutil.LevelBasic || len(data.Copies) != 1 {
		t.Fatalf("built-in = %+v, want basic with one copy", data)
	}
	if c := data.Copies[0]; c.BackupSerial != "usb-a" || c.BackupName != "Backup A" || !c.CopiedAt.Equal(fresh) || !c.Counts || c.Reason != "" {
		t.Errorf("copy = %+v, want the newest record on Backup A, counting", c)
	}
	backup := backupDrive(t, got, "usb-a")
	if backup.State != protectionutil.BackupStateCurrent || backup.Name != "Backup A" {
		t.Errorf("backup = %+v, want current", backup)
	}
	if len(backup.Holds) != 1 || backup.Holds[0].Serial != "" || backup.Holds[0].Name != "Built-in storage" || !backup.Holds[0].CopiedAt.Equal(fresh) {
		t.Errorf("holds = %+v, want built-in storage at %v", backup.Holds, fresh)
	}
	if backup.NewestCopy == nil || !backup.NewestCopy.Equal(fresh) {
		t.Errorf("newest copy = %v, want %v", backup.NewestCopy, fresh)
	}
}

func TestStatus_TwoFreshCopiesAreProtected(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now:   testNow,
		Roles: []protectionutil.Role{backupRole("usb-a"), backupRole("usb-b")},
		Devices: []protectionutil.Device{
			builtIn,
			{Serial: "usb-a", Name: "Shelf", DevicePath: "/dev/sdb1"},
			{Serial: "usb-b", Name: "Office", DevicePath: "/dev/sdc1"},
		},
		Copies: []protectionutil.Copy{copyOf("usb-a", "", fresh), copyOf("usb-b", "", fresh.Add(time.Minute))},
	})
	if got.Level != protectionutil.LevelProtected || got.NextStep != protectionutil.NextStepKeepElsewhere {
		t.Fatalf("status = %+v, want protected and keep-one-elsewhere", got)
	}
	const want = "Every drive is on two backup drives. Keep one somewhere else."
	if got.Sentence != want {
		t.Errorf("sentence = %q, want %q", got.Sentence, want)
	}
	copies := dataDrive(t, got, "").Copies
	if len(copies) != 2 || copies[0].BackupSerial != "usb-b" || copies[1].BackupSerial != "usb-a" {
		t.Errorf("copies = %+v, want both, newest first", copies)
	}
}

// A backup drive is never a data drive, so a record of one backup drive on
// another is not reported, and only the drives holding files are judged.
func TestStatus_BackupDrivesAreNotDataDrives(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now: testNow,
		Roles: []protectionutil.Role{
			backupRole("usb-a"), backupRole("usb-b"), {Serial: "main", Role: "default-storage"},
		},
		Devices: []protectionutil.Device{
			builtIn,
			{Serial: "main", Name: "Main", DevicePath: "/dev/sdd1"},
			{Serial: "usb-a", Name: "A", DevicePath: "/dev/sdb1"},
			{Serial: "usb-b", Name: "B", DevicePath: "/dev/sdc1"},
		},
		Copies: []protectionutil.Copy{
			copyOf("usb-a", "", fresh), copyOf("usb-a", "main", fresh), copyOf("usb-a", "usb-b", fresh),
		},
	})
	if len(got.DataDrives) != 2 || got.DataDrives[0].Serial != "" || got.DataDrives[1].Serial != "main" {
		t.Fatalf("data drives = %+v, want built-in storage and main", got.DataDrives)
	}
	if len(got.BackupDrives) != 2 {
		t.Fatalf("backup drives = %+v, want usb-a and usb-b", got.BackupDrives)
	}
	if holds := backupDrive(t, got, "usb-a").Holds; len(holds) != 2 {
		t.Errorf("usb-a holds = %+v, want only the two data drives", holds)
	}
	if got.Level != protectionutil.LevelBasic || got.NextStep != protectionutil.NextStepStartBackup {
		t.Errorf("status = %+v, want basic and start-backup onto usb-b", got)
	}
	if state := backupDrive(t, got, "usb-b").State; state != protectionutil.BackupStateNoCopies {
		t.Errorf("usb-b state = %s, want no-copies", state)
	}
}

// A copy on built-in storage protects a USB main-storage drive (#4022), and a
// backup drive on the same disk as the data drive is no copy of it.
func TestStatus_DifferentDiskRule(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now: testNow,
		Roles: []protectionutil.Role{
			backupRole(""), backupRole("main-part"), {Serial: "main", Role: "default-storage"},
		},
		Devices: []protectionutil.Device{
			builtIn,
			{Serial: "main", Name: "Main", DevicePath: "/dev/sda1"},
			{Serial: "main-part", Name: "Same disk", DevicePath: "/dev/sda2"},
		},
		Copies: []protectionutil.Copy{copyOf("", "main", fresh), copyOf("main-part", "main", fresh)},
	})
	main := dataDrive(t, got, "main")
	if main.Level != protectionutil.LevelBasic || len(main.Copies) != 2 {
		t.Fatalf("main = %+v, want basic with two copies", main)
	}
	for _, c := range main.Copies {
		switch c.BackupSerial {
		case "":
			if !c.Counts || c.BackupName != "Built-in storage" {
				t.Errorf("copy on built-in storage = %+v, want it to count", c)
			}
		case "main-part":
			if c.Counts || c.Reason != protectionutil.ReasonSameDisk {
				t.Errorf("copy on the same disk = %+v, want it not to count", c)
			}
		}
	}
	if len(got.DataDrives) != 1 {
		t.Errorf("data drives = %+v, want only main: built-in storage is a backup drive", got.DataDrives)
	}
	// The same-disk drive can never give main another copy, and nothing else can.
	if got.NextStep != protectionutil.NextStepAssignRole {
		t.Errorf("next = %s, want assign-backup-role", got.NextStep)
	}
}

func TestStatus_StaleCopy(t *testing.T) {
	// A copy exactly StaleAfter old is stale, matching backup_stale.
	stale := testNow.Add(-protectionutil.StaleAfter)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now:     testNow,
		Roles:   []protectionutil.Role{backupRole("usb-a")},
		Devices: []protectionutil.Device{builtIn, {Serial: "usb-a", Name: "A", DevicePath: "/dev/sdb1"}},
		Copies:  []protectionutil.Copy{copyOf("usb-a", "", stale)},
	})
	if got.Level != protectionutil.LevelUnprotected || got.NextStep != protectionutil.NextStepStartBackup {
		t.Fatalf("status = %+v, want unprotected and start-backup", got)
	}
	const want = "Built-in storage has no recent backup. Back up onto your backup drive."
	if got.Sentence != want {
		t.Errorf("sentence = %q, want %q", got.Sentence, want)
	}
	copies := dataDrive(t, got, "").Copies
	if len(copies) != 1 || copies[0].Counts || copies[0].Reason != protectionutil.ReasonStale {
		t.Errorf("copies = %+v, want one stale copy", copies)
	}
	if state := backupDrive(t, got, "usb-a").State; state != protectionutil.BackupStateBehind {
		t.Errorf("state = %s, want behind", state)
	}
}

func TestStatus_ReplaceSoonIsRetired(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now:   testNow,
		Roles: []protectionutil.Role{backupRole("worn"), backupRole("good")},
		Devices: []protectionutil.Device{
			builtIn,
			{Serial: "worn", Name: "Worn", DevicePath: "/dev/sdb1", ReplaceSoon: true},
			{Serial: "good", Name: "Good", DevicePath: "/dev/sdc1"},
		},
		Copies:    []protectionutil.Copy{copyOf("worn", "", fresh), copyOf("good", "", fresh)},
		Receiving: []string{"worn"},
	})
	if got.Level != protectionutil.LevelBasic || got.NextStep != protectionutil.NextStepAssignRole {
		t.Fatalf("status = %+v, want basic and assign-backup-role", got)
	}
	for _, c := range dataDrive(t, got, "").Copies {
		if c.BackupSerial == "worn" && (c.Counts || c.Reason != protectionutil.ReasonReplaceSoon) {
			t.Errorf("copy on the worn drive = %+v, want it not to count", c)
		}
	}
	if state := backupDrive(t, got, "worn").State; state != protectionutil.BackupStateRetired {
		t.Errorf("worn state = %s, want retired before receiving", state)
	}
}

func TestStatus_TwoPartitionsOfOneBackupDiskCountOnce(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	for name, paths := range map[string][2]string{
		"mac":   {"/dev/disk3s1", "/dev/disk3s5"},
		"linux": {"/dev/sda1", "/dev/sda2"},
	} {
		t.Run(name, func(t *testing.T) {
			got := protectionutil.Status(protectionutil.StatusParams{
				Now:   testNow,
				Roles: []protectionutil.Role{backupRole("part-b"), backupRole("part-a")},
				Devices: []protectionutil.Device{
					builtIn,
					{Serial: "part-a", Name: "A", DevicePath: paths[0]},
					{Serial: "part-b", Name: "B", DevicePath: paths[1]},
				},
				Copies: []protectionutil.Copy{copyOf("part-a", "", fresh), copyOf("part-b", "", fresh)},
			})
			if got.Level != protectionutil.LevelBasic || got.NextStep != protectionutil.NextStepAssignRole {
				t.Fatalf("status = %+v, want basic and assign-backup-role", got)
			}
			for _, c := range dataDrive(t, got, "").Copies {
				counts := c.BackupSerial == "part-a"
				if c.Counts != counts || (!counts && c.Reason != protectionutil.ReasonDuplicateDisk) {
					t.Errorf("copy %+v, want only part-a to count", c)
				}
			}
		})
	}
}

// The whole Quark is as protected as its weakest data drive, and the next
// step names the backup drive that could give that drive another copy.
func TestStatus_LevelIsTheWeakestDataDrive(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now:   testNow,
		Roles: []protectionutil.Role{backupRole("usb-a"), backupRole("usb-b")},
		Devices: []protectionutil.Device{
			builtIn,
			{Serial: "photos", Name: "Photos", DevicePath: "/dev/sdd1"},
			{Serial: "usb-a", Name: "A", DevicePath: "/dev/sdb1"},
			{Serial: "usb-b", Name: "B", DevicePath: "/dev/sdc1"},
		},
		Copies: []protectionutil.Copy{
			copyOf("usb-a", "", fresh), copyOf("usb-b", "", fresh), copyOf("usb-a", "photos", fresh),
		},
	})
	if dataDrive(t, got, "").Level != protectionutil.LevelProtected || dataDrive(t, got, "photos").Level != protectionutil.LevelBasic {
		t.Fatalf("data drives = %+v, want built-in protected and photos basic", got.DataDrives)
	}
	if got.Level != protectionutil.LevelBasic || got.NextStep != protectionutil.NextStepStartBackup {
		t.Fatalf("status = %+v, want basic and start-backup", got)
	}
	const want = "Every drive has a copy on one backup drive. Back up onto your other backup drive."
	if got.Sentence != want {
		t.Errorf("sentence = %q, want %q", got.Sentence, want)
	}
	if state := backupDrive(t, got, "usb-a").State; state != protectionutil.BackupStateCurrent {
		t.Errorf("usb-a = %s, want current", state)
	}
	if state := backupDrive(t, got, "usb-b").State; state != protectionutil.BackupStateBehind {
		t.Errorf("usb-b = %s, want behind: it lacks photos", state)
	}
}

// An unplugged backup drive is away, and its records still count.
func TestStatus_AwayAndReceiving(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now: testNow,
		Roles: []protectionutil.Role{
			{Serial: "gone", Role: "snapshot-backup", Name: "Offsite"},
			backupRole("busy"),
		},
		Devices:   []protectionutil.Device{builtIn, {Serial: "busy", Name: "Busy", DevicePath: "/dev/sdb1"}},
		Copies:    []protectionutil.Copy{copyOf("gone", "", fresh)},
		Receiving: []string{"busy"},
	})
	gone := backupDrive(t, got, "gone")
	if gone.State != protectionutil.BackupStateAway || gone.Name != "Offsite" {
		t.Errorf("gone = %+v, want away and named from its role", gone)
	}
	if got.Level != protectionutil.LevelBasic {
		t.Errorf("level = %s, want basic from the away drive's record", got.Level)
	}
	if state := backupDrive(t, got, "busy").State; state != protectionutil.BackupStateReceiving {
		t.Errorf("busy = %s, want receiving", state)
	}
	if b := backupDrive(t, got, "busy"); b.Holds == nil || len(b.Holds) != 0 || b.NewestCopy != nil {
		t.Errorf("busy = %+v, want no holds and no newest copy", b)
	}
}

// Two unplugged backup drives have no paths. Each stands alone, so both count.
func TestStatus_EmptyDevicePathStandsAlone(t *testing.T) {
	fresh := testNow.Add(-time.Hour)
	got := protectionutil.Status(protectionutil.StatusParams{
		Now:     testNow,
		Roles:   []protectionutil.Role{backupRole("usb-a"), backupRole("usb-b")},
		Devices: []protectionutil.Device{{Serial: "", Name: "Built-in storage"}},
		Copies:  []protectionutil.Copy{copyOf("usb-a", "", fresh), copyOf("usb-b", "", fresh)},
	})
	if got.Level != protectionutil.LevelProtected {
		t.Errorf("level = %s, want protected (%+v)", got.Level, got.DataDrives)
	}
}
