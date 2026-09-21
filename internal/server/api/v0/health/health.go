// Package v0_health serves /api/v0/health, the device metrics the Health page shows.
package v0_health

import (
	"github.com/autobutler-org/quark/pkg/util/healthutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

func NewRouter(collector *healthutil.Collector) serverutil.Router {
	return &router{collector: collector}
}
