package restartutil

import (
	"os"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// supervised reports whether something starts Quark again after it exits.
func supervised() bool {
	if updateutil.RunningAsInstalledService() {
		return true
	}
	on, err := strconv.ParseBool(os.Getenv(SupervisedEnv))
	return err == nil && on
}
