package db

import (
	"strings"
	"testing"
)

// Startup refuses a PostgreSQL server that is too old or can lose an
// acknowledged commit, and accepts every synchronous_commit that flushes the
// local WAL.
func TestCheckPostgresDurability(t *testing.T) {
	for _, tc := range []struct {
		name              string
		versionNum        int
		fsync, syncCommit string
		// wantErr is what the refusal has to say; empty means accepted.
		wantErr string
	}{
		{name: "18, durable", versionNum: 180001, fsync: "on", syncCommit: "on"},
		{name: "14 is the oldest", versionNum: 140000, fsync: "on", syncCommit: "on"},
		{name: "local", versionNum: 170000, fsync: "on", syncCommit: "local"},
		{name: "remote_write", versionNum: 170000, fsync: "on", syncCommit: "remote_write"},
		{name: "remote_apply", versionNum: 170000, fsync: "on", syncCommit: "remote_apply"},
		{name: "13 is too old", versionNum: 130016, fsync: "on", syncCommit: "on", wantErr: "PostgreSQL 13.16, and Quark needs PostgreSQL 14"},
		{name: "fsync off", versionNum: 180001, fsync: "off", syncCommit: "on", wantErr: "fsync = off"},
		{name: "synchronous_commit off", versionNum: 180001, fsync: "on", syncCommit: "off", wantErr: "ALTER ROLE <user> SET synchronous_commit = on"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := checkPostgresDurability(tc.versionNum, tc.fsync, tc.syncCommit)
			if tc.wantErr == "" {
				if err != nil {
					t.Fatalf("refused: %v", err)
				}
				return
			}
			if err == nil || !strings.Contains(err.Error(), tc.wantErr) {
				t.Fatalf("got %v, want a refusal saying %q", err, tc.wantErr)
			}
		})
	}
}
