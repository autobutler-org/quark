package repairutil

import (
	"os"
	"strings"
)

func unavailableReason(system System) Reason {
	if reason := system.Service(); reason != ReasonNone {
		return reason
	}
	if !unitReappliesSetup(system.UnitPath) {
		return ReasonUnitOutdated
	}
	return ReasonNone
}

// unitReappliesSetup reports whether the unit at path has an ExecStartPre that
// runs `install --system-only`. Reading it whole is fine: `quark install`
// writes it, and it is a few hundred bytes. A missing or unreadable unit
// cannot be shown to repair anything, so it counts as outdated.
func unitReappliesSetup(path string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	for line := range strings.SplitSeq(string(data), "\n") {
		value, ok := strings.CutPrefix(strings.TrimSpace(line), "ExecStartPre=")
		if ok && strings.Contains(value, " install --system-only") {
			return true
		}
	}
	return false
}
