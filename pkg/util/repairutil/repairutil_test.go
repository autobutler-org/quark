package repairutil

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// currentUnit is the relevant part of the unit `quark install` writes since
// #2120. internal/install checks its real unit against GetStatus too.
const currentUnit = `[Service]
User=quark
ExecStartPre=-+/opt/quark/bin/quark install --system-only
ExecStart=/opt/quark/bin/quark serve
Restart=always
`

const outdatedUnit = `[Service]
User=quark
ExecStart=/opt/quark/bin/quark serve
Restart=always
`

const commentedUnit = `[Service]
# ExecStartPre=-+/opt/quark/bin/quark install --system-only
ExecStart=/opt/quark/bin/quark serve
`

func writeUnit(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "quark.service")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func fakeSystem(service Reason, unitPath string, restart func() error) System {
	return System{Service: func() Reason { return service }, UnitPath: unitPath, Restart: restart}
}

func TestGetStatus(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "absent.service")
	cases := []struct {
		name     string
		service  Reason
		unitPath string
		want     Reason
	}{
		{"current unit", ReasonNone, writeUnit(t, currentUnit), ReasonNone},
		{"unit before #2120", ReasonNone, writeUnit(t, outdatedUnit), ReasonUnitOutdated},
		{"commented-out line", ReasonNone, writeUnit(t, commentedUnit), ReasonUnitOutdated},
		{"missing unit", ReasonNone, missing, ReasonUnitOutdated},
		{"not Linux", ReasonUnsupportedOS, writeUnit(t, currentUnit), ReasonUnsupportedOS},
		{"not the service", ReasonNotService, writeUnit(t, currentUnit), ReasonNotService},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := GetStatus(GetStatusParams{System: fakeSystem(tc.service, tc.unitPath, nil)})
			if err != nil {
				t.Fatal(err)
			}
			if got.Reason != tc.want || got.Available != (tc.want == ReasonNone) {
				t.Errorf("GetStatus = %+v, want reason %q", got, tc.want)
			}
		})
	}
}

func TestRepairRefusesWhenUnavailable(t *testing.T) {
	restarted := false
	system := fakeSystem(ReasonNone, writeUnit(t, outdatedUnit), func() error { restarted = true; return nil })
	if _, err := Repair(RepairParams{System: system}); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("Repair err = %v, want ErrUnavailable", err)
	}
	if restarted {
		t.Error("Repair restarted although unavailable")
	}
}

func TestRepairRestarts(t *testing.T) {
	restarted := false
	system := fakeSystem(ReasonNone, writeUnit(t, currentUnit), func() error { restarted = true; return nil })
	if _, err := Repair(RepairParams{System: system}); err != nil {
		t.Fatal(err)
	}
	if !restarted {
		t.Fatal("Repair did not restart")
	}
}

// A repair is a restart, so it takes the guard an update holds: a second
// restart, repair or update while one is pending is refused (#4019).
func TestRepairRefusesWhileRestartPending(t *testing.T) {
	t.Cleanup(updateutil.SetRestartExitForTest(func(int) {}))
	if err := updateutil.ScheduleRestart(); err != nil {
		t.Fatal(err)
	}
	system := fakeSystem(ReasonNone, writeUnit(t, currentUnit), updateutil.ScheduleRestart)
	if _, err := Repair(RepairParams{System: system}); !errors.Is(err, updateutil.ErrUpdateInProgress) {
		t.Fatalf("Repair err = %v, want ErrUpdateInProgress", err)
	}
}

func TestDefaultSystemOffService(t *testing.T) {
	// Tests never run as the installed service, so the real host is refused
	// before the unit is read.
	got, err := GetStatus(GetStatusParams{System: DefaultSystem()})
	if err != nil {
		t.Fatal(err)
	}
	if got.Reason != ReasonUnsupportedOS && got.Reason != ReasonNotService {
		t.Errorf("GetStatus(DefaultSystem) = %+v, want unsupported_os or not_service", got)
	}
}
