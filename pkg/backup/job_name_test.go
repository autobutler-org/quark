package backup

import "testing"

func TestBackupJobName(t *testing.T) {
	for _, tc := range []struct {
		name   string
		names  map[string]string
		target string
		want   string
		// backups are the backup drives besides the target.
		backups []string
		// chosen are the sources asked for; none is every data drive.
		chosen []string
	}{
		{"no devices listed", map[string]string{}, "USB-1", "Back up onto drive USB-1", nil, nil},
		{"onto built-in storage", map[string]string{"": "Macintosh HD", "90C82C65AB": "Quark"}, "",
			"Back up Quark onto Built-in storage", nil, nil},
		{"two sources", map[string]string{"": "Built-in storage", "A": "Photos", "B": "Backup"}, "B",
			"Back up Built-in storage, Photos onto Backup", nil, nil},
		{"more than two", map[string]string{"": "", "A": "Photos", "B": "Music", "C": "Backup", "SERIAL-123456789": ""}, "C",
			"Back up Built-in storage, Music and 2 more onto Backup", nil, nil},
		{"other backup drives are not sources", map[string]string{"": "", "A": "Photos", "B": "Backup B", "C": "Backup"}, "C",
			"Back up Built-in storage, Photos onto Backup", []string{"B"}, nil},
		{"only the chosen sources", map[string]string{"": "", "A": "Photos", "B": "Music", "C": "Backup"}, "C",
			"Back up Music, Photos onto Backup", nil, []string{"B", "A"}},
		{"a chosen source nobody named", map[string]string{}, "C",
			"Back up Built-in storage onto drive C", nil, []string{""}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			backups := map[string]bool{tc.target: true}
			for _, serial := range tc.backups {
				backups[serial] = true
			}
			if got := backupJobName(tc.names, backups, tc.target, tc.chosen); got != tc.want {
				t.Errorf("backupJobName = %q, want %q", got, tc.want)
			}
		})
	}
	if got := restoreJobName(map[string]string{"A": "Backup"}, "A"); got != "Restore files from Backup" {
		t.Errorf("restoreJobName = %q", got)
	}
}
