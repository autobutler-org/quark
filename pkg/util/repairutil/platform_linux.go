//go:build linux

package repairutil

import "github.com/autobutler-org/quark/pkg/util/updateutil"

func serviceReason() Reason {
	if !updateutil.RunningAsInstalledService() {
		return ReasonNotService
	}
	return ReasonNone
}
