// Package repairutil lets an admin repair the Quark installation (#2121).
//
// Repair is a restart and nothing more: the unit `quark install` writes runs
// `quark install --system-only` as root in ExecStartPre before every start
// (#2120), which rewrites the system setup. So the service needs no new
// privilege; it exits the way self-update does and systemd brings it back.
// That only helps when this is the installed service and its unit carries
// that line, so GetStatus says whether it will.
package repairutil

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// UnitPath is where `quark install` writes the systemd unit.
const UnitPath = "/etc/systemd/system/quark.service"

// Reason says why the installation cannot be repaired from Quark.
type Reason string

const (
	// ReasonNone means a repair will work.
	ReasonNone Reason = ""
	// ReasonUnsupportedOS means the Quark is not running on Linux.
	ReasonUnsupportedOS Reason = "unsupported_os"
	// ReasonNotService means Quark is not running as its installed systemd
	// service, as the quark user, from /opt/quark/bin.
	ReasonNotService Reason = "not_service"
	// ReasonUnitOutdated means the installed unit predates the ExecStartPre
	// line that reapplies the system setup, so a restart would change nothing.
	// A one-time `sudo quark install` writes the current unit.
	ReasonUnitOutdated Reason = "unit_outdated"
)

// ErrUnavailable is returned by Repair when a repair would not work;
// GetStatus says why.
var ErrUnavailable = errors.New("the installation can't be repaired from Quark on this device")

// System is everything repairutil touches on the host, so tests can swap it.
type System struct {
	// Service reports why this process is not the installed Linux service
	// (ReasonUnsupportedOS or ReasonNotService), or ReasonNone.
	Service func() Reason
	// UnitPath is the installed systemd unit to inspect.
	UnitPath string
	// Restart exits the process so the service manager starts it again. It
	// runs in its own goroutine and should give the response time to go out.
	Restart func()
}

// DefaultSystem is the real host.
func DefaultSystem() System {
	return System{
		Service:  serviceReason,
		UnitPath: UnitPath,
		Restart:  updateutil.ExitForRestart,
	}
}

type GetStatusParams struct {
	System System
}

type GetStatusResult struct {
	// Available is whether a repair will work here.
	Available bool
	// Reason says why not, when Available is false.
	Reason Reason
}

// GetStatus reports whether a repair will work, checking the conditions in
// the order to fix them.
func GetStatus(params GetStatusParams) (GetStatusResult, error) {
	reason := unavailableReason(params.System)
	return GetStatusResult{Available: reason == ReasonNone, Reason: reason}, nil
}

type RepairParams struct {
	System System
}

type RepairResult struct{}

// Repair starts the restart in the background and returns at once, so the
// caller can answer before the process exits. It refuses with ErrUnavailable
// when GetStatus would say no.
func Repair(params RepairParams) (RepairResult, error) {
	if unavailableReason(params.System) != ReasonNone {
		return RepairResult{}, ErrUnavailable
	}
	go params.System.Restart()
	return RepairResult{}, nil
}
