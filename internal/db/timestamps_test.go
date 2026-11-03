package db_test

import (
	"context"
	"regexp"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// TestSQLStampsMilliseconds checks a row stamped by a query on SQLite carries
// milliseconds, so two rows written within one second sort in write order, as
// they do on PostgreSQL (#3170).
func TestSQLStampsMilliseconds(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	millis := regexp.MustCompile(`^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3}$`)

	stamps := make([]string, 0, 2)
	for _, serial := range []string{"first", "second"} {
		if err := database.Queries.UpsertDeviceName(ctx, db.UpsertDeviceNameParams{DeviceSerial: serial, DisplayName: "disk"}); err != nil {
			t.Fatalf("UpsertDeviceName(%s): %v", serial, err)
		}
		var stamp string
		if err := database.Db.QueryRow(`SELECT CAST(updated_at AS TEXT) FROM device_names WHERE device_serial = ?`, serial).Scan(&stamp); err != nil {
			t.Fatalf("read %s: %v", serial, err)
		}
		if !millis.MatchString(stamp) {
			t.Errorf("%s stamped %q, want milliseconds", serial, stamp)
		}
		stamps = append(stamps, stamp)
		time.Sleep(2 * time.Millisecond)
	}
	if stamps[0] >= stamps[1] {
		t.Errorf("first row stamped %q, not before the second's %q", stamps[0], stamps[1])
	}

	// The driver reads the millisecond form back as a time.Time.
	var updated time.Time
	if err := database.Db.QueryRow(`SELECT updated_at FROM device_names WHERE device_serial = 'first'`).Scan(&updated); err != nil {
		t.Fatalf("scan updated_at as a time: %v", err)
	}
	if got := updated.UTC().Format("2006-01-02 15:04:05.000"); got != stamps[0] {
		t.Errorf("updated_at read back as %s, want %s", got, stamps[0])
	}
}
