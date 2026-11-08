package backup

import "testing"

func TestBackupJobName(t *testing.T) {
	for _, tc := range []struct {
		name   string
		names  map[string]string
		target string
		want   string
	}{
		{"no devices listed", map[string]string{}, "USB-1", "Back up onto drive USB-1"},
		{"onto built-in storage", map[string]string{"": "Macintosh HD", "90C82C65AB": "Quark"}, "",
			"Back up Quark onto Built-in storage"},
		{"two sources", map[string]string{"": "Built-in storage", "A": "Photos", "B": "Backup"}, "B",
			"Back up Built-in storage, Photos onto Backup"},
		{"more than two", map[string]string{"": "", "A": "Photos", "B": "Music", "C": "Backup", "SERIAL-123456789": ""}, "C",
			"Back up Built-in storage, Music and 2 more onto Backup"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := backupJobName(tc.names, tc.target); got != tc.want {
				t.Errorf("backupJobName = %q, want %q", got, tc.want)
			}
		})
	}
	if got := restoreJobName(map[string]string{"A": "Backup"}, "A"); got != "Restore files from Backup" {
		t.Errorf("restoreJobName = %q", got)
	}
}
