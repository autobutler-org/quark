// Package restartutil lets an admin restart Quark from Settings (#4019).
//
// Quark restarts by exiting and leaving its supervisor to start it again, the
// way self-update and repair do. So a restart is offered only where something
// will: the installed systemd service, whose unit has Restart=always, or a
// container whose operator set QUARK_RESTART_SUPERVISED beside a restart
// policy. The image cannot know its container's --restart policy, so it does
// not set the variable. Anywhere else the process would simply stop.
package restartutil

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// SupervisedEnv names the variable an operator sets to a true value
// (strconv.ParseBool) to say a supervisor starts Quark again after it exits.
const SupervisedEnv = "QUARK_RESTART_SUPERVISED"

// Reason says why Quark cannot restart itself here.
type Reason string

const (
	// ReasonNone means a restart will work.
	ReasonNone Reason = ""
	// ReasonNotSupervised means nothing is known to start Quark again after
	// it exits: it is not the installed service and SupervisedEnv is not set.
	ReasonNotSupervised Reason = "not_supervised"
)

// ErrUnsupervised is returned by Restart when nothing would start Quark again.
var ErrUnsupervised = errors.New("nothing on this device would start Quark again, so it can't restart itself")

type GetStatusParams struct{}

type GetStatusResult struct {
	// Available is whether a restart will bring Quark back.
	Available bool
	// Reason says why not, when Available is false.
	Reason Reason
}

// GetStatus reports whether a restart will bring Quark back.
func GetStatus(GetStatusParams) (GetStatusResult, error) {
	if !supervised() {
		return GetStatusResult{Reason: ReasonNotSupervised}, nil
	}
	return GetStatusResult{Available: true}, nil
}

type RestartParams struct{}

type RestartResult struct{}

// Restart schedules the exit and returns at once, so the caller can answer
// before the process exits about two seconds later. It refuses with
// ErrUnsupervised when GetStatus would say no, and with
// updateutil.ErrUpdateInProgress when an update, restart or repair is already
// under way.
func Restart(RestartParams) (RestartResult, error) {
	if !supervised() {
		return RestartResult{}, ErrUnsupervised
	}
	return RestartResult{}, updateutil.ScheduleRestart()
}
