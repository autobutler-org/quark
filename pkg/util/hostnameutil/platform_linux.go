//go:build linux

package hostnameutil

import (
	"os"

	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// unavailableReason checks, in the order to fix them, that this Quark is the
// installed service and that `quark install` has written the helper.
func unavailableReason() Reason {
	if !updateutil.RunningAsInstalledService() {
		return ReasonNotService
	}
	if _, err := os.Stat(HelperPath); err != nil {
		return ReasonHelperMissing
	}
	return ReasonNone
}
