package repairutil

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
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

func fakeSystem(service Reason, unitPath string, restart func()) System {
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
	system := fakeSystem(ReasonNone, writeUnit(t, outdatedUnit), func() { restarted = true })
	if _, err := Repair(RepairParams{System: system}); !errors.Is(err, ErrUnavailable) {
		t.Fatalf("Repair err = %v, want ErrUnavailable", err)
	}
	if restarted {
		t.Error("Repair restarted although unavailable")
	}
}

func TestRepairRestarts(t *testing.T) {
	restarted := make(chan struct{})
	system := fakeSystem(ReasonNone, writeUnit(t, currentUnit), func() { close(restarted) })
	if _, err := Repair(RepairParams{System: system}); err != nil {
		t.Fatal(err)
	}
	select {
	case <-restarted:
	case <-time.After(5 * time.Second):
		t.Fatal("Repair did not restart")
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
