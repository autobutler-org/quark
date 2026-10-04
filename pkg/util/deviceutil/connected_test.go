package deviceutil

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db/dbtest"
)

// One row per distinct (IP, User-Agent) was written on every request and
// never removed (#2756). A client cycling its User-Agent must not grow the
// table past the cap, and the peers kept are the most recent.
func TestRecordConnectedDevice_NewPeersNeverGrowPastTheCap(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	const extra = 10
	for i := range MaxConnectedDevices + extra {
		if _, err := RecordConnectedDevice(ctx, RecordConnectedDeviceParams{Database: database, IPAddress: "10.0.0.1", UserAgent: fmt.Sprintf("agent-%d", i)}); err != nil {
			t.Fatal(err)
		}
	}
	count, err := database.Queries.CountConnectedDevices(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if count != MaxConnectedDevices {
		t.Errorf("connected_devices holds %d rows, want the cap %d", count, MaxConnectedDevices)
	}
	rows, err := database.Queries.ListConnectedDevices(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, row := range rows {
		var i int
		if _, err := fmt.Sscanf(row.UserAgent, "agent-%d", &i); err != nil || i < extra {
			t.Errorf("kept %q, want only the %d newest peers", row.UserAgent, MaxConnectedDevices)
		}
	}
}

// A returning peer is the common case and costs no prune.
func TestRecordConnectedDevice_ReturningPeerDoesNotPrune(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	params := RecordConnectedDeviceParams{Database: database, IPAddress: "10.0.0.1", UserAgent: "app"}
	first, err := RecordConnectedDevice(ctx, params)
	if err != nil {
		t.Fatal(err)
	}
	again, err := RecordConnectedDevice(ctx, params)
	if err != nil {
		t.Fatal(err)
	}
	if !first.New || again.New {
		t.Errorf("New = %v then %v, want true then false", first.New, again.New)
	}
}

func TestPruneConnectedDevices_DropsPeersNotSeenForTheMaxAge(t *testing.T) {
	database := dbtest.NewDB(t)
	ctx := context.Background()
	if _, err := RecordConnectedDevice(ctx, RecordConnectedDeviceParams{Database: database, IPAddress: "10.0.0.1", UserAgent: "app"}); err != nil {
		t.Fatal(err)
	}

	notYet, err := PruneConnectedDevices(ctx, PruneConnectedDevicesParams{Database: database, Now: time.Now().Add(ConnectedDeviceMaxAge - time.Hour)})
	if err != nil {
		t.Fatal(err)
	}
	if notYet.Removed != 0 {
		t.Errorf("Removed = %d before the max age, want 0", notYet.Removed)
	}
	later, err := PruneConnectedDevices(ctx, PruneConnectedDevicesParams{Database: database, Now: time.Now().Add(ConnectedDeviceMaxAge + time.Hour)})
	if err != nil {
		t.Fatal(err)
	}
	if later.Removed != 1 {
		t.Errorf("Removed = %d past the max age, want 1", later.Removed)
	}
}
