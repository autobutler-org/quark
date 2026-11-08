// cspell:ignore protectionutil

package protectionutil

import "time"

const roleSnapshotBackup = "snapshot-backup"

// drive is one data or backup drive joined with its device.
type drive struct {
	serial      string
	name        string
	diskKey     string
	connected   bool
	replaceSoon bool
}

// inputs is StatusParams joined up: the data drives and backup drives, each
// ordered by serial, and the newest copy per backup drive and data drive.
type inputs struct {
	data      []drive
	backups   []drive
	copies    map[string]map[string]time.Time
	receiving map[string]bool
}
