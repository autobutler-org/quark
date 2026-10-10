package notificationutil_test

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/backup"
	"github.com/autobutler-org/quark/pkg/util/notificationutil"
)

func TestList_BackupNotifications(t *testing.T) {
	now := time.Date(2026, 10, 9, 12, 0, 0, 0, time.UTC)
	never := time.Time{}
	fresh := now.Add(-notificationutil.BackupStaleAfter + time.Second)
	atThreshold := now.Add(-notificationutil.BackupStaleAfter)
	stale := now.Add(-2 * notificationutil.BackupStaleAfter)

	tests := []struct {
		name       string
		isAdmin    bool
		lastBackup time.Time
		disabled   []notificationutil.Type
		want       notificationutil.Type // empty means no notification
	}{
		{name: "non-admin never backed up", lastBackup: never},
		{name: "non-admin with a stale backup", lastBackup: stale},
		{name: "never backed up", isAdmin: true, lastBackup: never, want: notificationutil.TypeBackupDue},
		{name: "fresh backup", isAdmin: true, lastBackup: fresh},
		{name: "exactly at the threshold", isAdmin: true, lastBackup: atThreshold, want: notificationutil.TypeBackupStale},
		{name: "stale backup", isAdmin: true, lastBackup: stale, want: notificationutil.TypeBackupStale},
		{
			name: "due turned off", isAdmin: true, lastBackup: never,
			disabled: []notificationutil.Type{notificationutil.TypeBackupDue},
		},
		{
			name: "stale turned off", isAdmin: true, lastBackup: stale,
			disabled: []notificationutil.Type{notificationutil.TypeBackupStale},
		},
		{
			name: "due turned off does not hide stale", isAdmin: true, lastBackup: stale,
			disabled: []notificationutil.Type{notificationutil.TypeBackupDue},
			want:     notificationutil.TypeBackupStale,
		},
		{
			name: "stale turned off does not hide due", isAdmin: true, lastBackup: never,
			disabled: []notificationutil.Type{notificationutil.TypeBackupStale},
			want:     notificationutil.TypeBackupDue,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := context.Background()
			queries := dbtest.NewDB(t).Queries
			if !tt.lastBackup.IsZero() {
				if err := backup.RecordSnapshot(ctx, queries, tt.lastBackup); err != nil {
					t.Fatal(err)
				}
			}
			result, err := notificationutil.List(ctx, notificationutil.ListParams{
				Queries: queries, IsAdmin: tt.isAdmin, Disabled: tt.disabled, Now: now,
			})
			if err != nil {
				t.Fatal(err)
			}
			got := result.Notifications
			if got == nil {
				t.Fatal("Notifications is nil; it must encode as []")
			}
			if tt.want == "" {
				if len(got) != 0 {
					t.Fatalf("Notifications = %+v, want none", got)
				}
				return
			}
			if len(got) != 1 || got[0].Type != tt.want || got[0].Link != notificationutil.BackupLink {
				t.Fatalf("Notifications = %+v, want one %s linking to %s", got, tt.want, notificationutil.BackupLink)
			}
			if tt.want == notificationutil.TypeBackupStale {
				if got[0].LastBackupAt == nil || !got[0].LastBackupAt.Equal(tt.lastBackup) {
					t.Errorf("LastBackupAt = %v, want %v", got[0].LastBackupAt, tt.lastBackup)
				}
			} else if got[0].LastBackupAt != nil {
				t.Errorf("LastBackupAt = %v on %s, want none", got[0].LastBackupAt, tt.want)
			}
		})
	}
}

func TestList_NoNotificationsEncodesAsEmptyArray(t *testing.T) {
	result, err := notificationutil.List(context.Background(), notificationutil.ListParams{Queries: dbtest.NewDB(t).Queries, Now: time.Now()})
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(result)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != `{"notifications":[]}` {
		t.Errorf("encoded = %s, want an empty array", data)
	}
}

func TestType_Valid(t *testing.T) {
	for _, typ := range notificationutil.Types() {
		if !typ.Valid() {
			t.Errorf("%q is listed by Types but not Valid", typ)
		}
	}
	for _, typ := range []notificationutil.Type{"", "backup_complete", "BACKUP_DUE"} {
		if typ.Valid() {
			t.Errorf("%q is Valid, want not", typ)
		}
	}
}
