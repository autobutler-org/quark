package backup

import (
	"errors"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// A schedule is due when its cadence is on and the newest run holding a
// scheduled source is older than the cadence, or there is none.
func TestIsDue(t *testing.T) {
	now := time.Date(2026, 11, 9, 12, 0, 0, 0, time.UTC)
	fresh := []RunCopy{{Serial: "", CompletedAt: now.Add(-time.Hour)}}
	stale := []RunCopy{{Serial: "", CompletedAt: now.Add(-25 * time.Hour)}}
	for _, tc := range []struct {
		name   string
		plan   schedule
		copies []RunCopy
		want   bool
	}{
		{"off", schedule{Cadence: cadenceOff}, nil, false},
		{"no run", schedule{Cadence: "daily"}, nil, true},
		{"fresh run", schedule{Cadence: "daily"}, fresh, false},
		{"stale run", schedule{Cadence: "daily"}, stale, true},
		{"stale run, weekly", schedule{Cadence: "weekly"}, stale, false},
		{"fresh copy of another drive only", schedule{Cadence: "daily", SourceSerials: []string{"PHOTOS"}}, fresh, true},
		{"fresh copy of one of the sources", schedule{Cadence: "daily", SourceSerials: []string{"", "PHOTOS"}}, fresh, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := isDue(tc.plan, tc.copies, now); got != tc.want {
				t.Errorf("isDue = %v, want %v", got, tc.want)
			}
		})
	}
}

// A drive with no schedule is off; a saved one reads back, sorted and
// deduplicated, and publishes backup_schedule_changed. A row nobody can read
// is off.
func TestSetSchedule_RoundTrip(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	get := func() GetScheduleResult {
		t.Helper()
		got, err := GetSchedule(GetScheduleParams{Ctx: t.Context(), Queries: f.database.Queries, Registry: f.registry, DeviceSerial: targetSerial})
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	if got := get(); got.Cadence != cadenceOff || got.Due || len(got.SourceSerials) != 0 || got.SourceSerials == nil {
		t.Fatalf("unset schedule = %+v, want off with no sources", got)
	}

	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	defer unsubscribe()
	if _, err := SetSchedule(SetScheduleParams{
		Ctx: t.Context(), Queries: f.database.Queries, Registry: f.registry, EventBus: bus,
		DeviceSerial: targetSerial, Cadence: "weekly", SourceSerials: []string{"PHOTOS", "", "PHOTOS"},
	}); err != nil {
		t.Fatal(err)
	}
	got := get()
	if got.Cadence != "weekly" || len(got.SourceSerials) != 2 || got.SourceSerials[0] != "" || got.SourceSerials[1] != "PHOTOS" {
		t.Fatalf("saved schedule = %+v, want weekly of built-in storage and PHOTOS", got)
	}
	if !got.Due || got.WaitingForDrive {
		t.Errorf("a schedule on an attached drive with no run = %+v, want due and not waiting", got)
	}
	select {
	case evt := <-events:
		if evt.Kind != eventbus.EventBackupScheduleChanged || evt.Data != (eventbus.BackupScheduleChanged{DeviceSerial: targetSerial}) {
			t.Errorf("event = %+v, want backup_schedule_changed for the drive", evt)
		}
	case <-time.After(time.Second):
		t.Error("no event published")
	}

	if err := f.database.Queries.SetSetting(t.Context(), db.SetSettingParams{Key: scheduleKeyPrefix + targetSerial, Value: "{"}); err != nil {
		t.Fatal(err)
	}
	if got := get(); got.Cadence != cadenceOff {
		t.Errorf("schedule from an unreadable row = %+v, want off", got)
	}
}

// An unknown cadence, a drive without the role, and a source that is the
// drive or another backup drive are refused. A drive that is away takes a
// schedule, and waits for it.
func TestSetSchedule_Validates(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	set := func(serial, cadence string, sources ...string) (SetScheduleResult, error) {
		return SetSchedule(SetScheduleParams{
			Ctx: t.Context(), Queries: f.database.Queries, Registry: f.registry,
			DeviceSerial: serial, Cadence: cadence, SourceSerials: sources,
		})
	}
	if _, err := set(targetSerial, "hourly"); !errors.Is(err, ErrUnknownCadence) {
		t.Errorf("hourly = %v, want ErrUnknownCadence", err)
	}
	if _, err := set("", "daily"); !errors.Is(err, ErrBackupRoleRequired) {
		t.Errorf("a data drive = %v, want ErrBackupRoleRequired", err)
	}
	for _, source := range []string{targetSerial, otherSerial} {
		if _, err := set(targetSerial, "daily", source); !errors.Is(err, ErrSourceNotDataDrive) {
			t.Errorf("source %q = %v, want ErrSourceNotDataDrive", source, err)
		}
	}

	if err := f.database.Queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{DeviceSerial: "AWAY", Role: "snapshot-backup"}); err != nil {
		t.Fatal(err)
	}
	got, err := set("AWAY", "daily", "GONE-1")
	if err != nil {
		t.Fatalf("a schedule for an away drive and source: %v", err)
	}
	if !got.Due || !got.WaitingForDrive {
		t.Errorf("away drive = %+v, want due and waiting for the drive", got)
	}
}

// startDue runs StartDueBackups over the fixture with a queue nobody runs, so
// every job it queues stays pending.
func startDue(t *testing.T, f jobFixture, inst instance) []string {
	t.Helper()
	result, err := StartDueBackups(StartDueBackupsParams{
		Ctx: t.Context(), Queries: f.database.Queries, Registry: f.registry, Queue: inst.queue,
	})
	if err != nil {
		t.Fatal(err)
	}
	return result.JobIDs
}

func setSchedule(t *testing.T, f jobFixture, serial, cadence string, sources ...string) {
	t.Helper()
	if _, err := SetSchedule(SetScheduleParams{
		Ctx: t.Context(), Queries: f.database.Queries, Registry: f.registry,
		DeviceSerial: serial, Cadence: cadence, SourceSerials: sources,
	}); err != nil {
		t.Fatal(err)
	}
}

// A due schedule on an attached drive starts a backup as the system; a
// second pass while it is pending starts nothing more, and a drive whose
// schedule is off is left alone.
func TestStartDueBackups_StartsWhenDueAndMountedOnce(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	inst := f.instance(nil)
	setSchedule(t, f, targetSerial, "daily")

	jobs := startDue(t, f, inst)
	if len(jobs) != 1 {
		t.Fatalf("jobs = %v, want one backup onto %s", jobs, targetSerial)
	}
	row, err := f.database.Queries.GetActiveBackupJob(t.Context(), targetSerial)
	if err != nil || row.UserID.Valid {
		t.Fatalf("active backup = %+v, %v; want a system job onto the target", row, err)
	}
	if _, err := f.database.Queries.GetActiveBackupJob(t.Context(), otherSerial); err == nil {
		t.Error("a backup started onto a drive whose schedule is off")
	}
	if jobs := startDue(t, f, inst); len(jobs) != 0 {
		t.Errorf("second pass = %v, want nothing while the first is pending", jobs)
	}
}

// A drive that is not attached, or one whose newest run is inside the
// cadence, starts nothing.
func TestStartDueBackups_SkipsUnmountedAndFresh(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	inst := f.instance(nil)
	if err := f.database.Queries.UpsertDeviceRole(t.Context(), db.UpsertDeviceRoleParams{DeviceSerial: "AWAY", Role: "snapshot-backup"}); err != nil {
		t.Fatal(err)
	}
	setSchedule(t, f, "AWAY", "daily")
	setSchedule(t, f, targetSerial, "daily")
	putRun(t, localFS(t, f.target), "2026-11-09 08.00", time.Now().Add(-time.Hour),
		[]ManifestDrive{{Folder: builtInFolder, Serial: "", Name: "Pi"}}, map[string]string{builtInFolder + "/a.txt": "a"})

	if jobs := startDue(t, f, inst); len(jobs) != 0 {
		t.Errorf("jobs = %v, want none", jobs)
	}
}

// A scheduled source that is no longer an attached data drive is left out
// of the run; when none is left, nothing starts.
func TestStartDueBackups_DropsSourcesThatAreGone(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	inst := f.instance(nil)
	setSchedule(t, f, targetSerial, "daily", "GONE-1")
	if jobs := startDue(t, f, inst); len(jobs) != 0 {
		t.Fatalf("jobs = %v, want none with every source gone", jobs)
	}

	setSchedule(t, f, targetSerial, "daily", "", "GONE-1")
	jobs := startDue(t, f, inst)
	if len(jobs) != 1 {
		t.Fatalf("jobs = %v, want one", jobs)
	}
	row, err := f.database.Queries.GetJob(t.Context(), mustID(t, jobs[0]))
	if err != nil {
		t.Fatal(err)
	}
	if want := `{"targetDeviceSerial":"` + targetSerial + `","sourceSerials":[""]}`; row.Params != want {
		t.Errorf("params = %s, want %s", row.Params, want)
	}
}

// A scheduled backup that failed leaves no run, so its drive stays due: the
// loop waits scheduleRetryAfter (or the cadence, if shorter) after the last
// start before starting another, and records each start it makes.
func TestStartDueBackups_BacksOffAfterAStart(t *testing.T) {
	f := newJobFixture(t, dbtest.NewDB(t))
	inst := f.instance(nil)
	startedAgo := func(ago time.Duration) {
		t.Helper()
		value := `{"cadence":"daily","sourceSerials":[],"lastStartedAt":"` + time.Now().Add(-ago).UTC().Format(time.RFC3339) + `"}`
		if err := f.database.Queries.SetSetting(t.Context(), db.SetSettingParams{Key: scheduleKeyPrefix + targetSerial, Value: value}); err != nil {
			t.Fatal(err)
		}
	}

	startedAgo(time.Hour)
	if jobs := startDue(t, f, inst); len(jobs) != 0 {
		t.Fatalf("jobs = %v, want none an hour after the last start", jobs)
	}
	startedAgo(7 * time.Hour)
	if jobs := startDue(t, f, inst); len(jobs) != 1 {
		t.Fatalf("jobs = %v, want one seven hours after the last start", jobs)
	}
	plan, err := readSchedule(t.Context(), f.database.Queries, targetSerial)
	if err != nil {
		t.Fatal(err)
	}
	if time.Since(plan.LastStartedAt) > time.Minute {
		t.Errorf("lastStartedAt = %v, want the start just made", plan.LastStartedAt)
	}
}
