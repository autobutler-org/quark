package workerutil

import (
	"context"
	"log"

	"github.com/autobutler-org/quark/internal/db"
)

// claimTurn reports whether this caller took the task's turn for the current
// interval.
func claimTurn(ctx context.Context, params RunPeriodicallyParams, owner string) bool {
	err := params.Queries.EnsureMaintenanceRun(ctx, params.Name)
	var claimed int64
	if err == nil {
		claimed, err = params.Queries.ClaimMaintenanceRun(ctx, db.ClaimMaintenanceRunParams{
			Owner:           owner,
			Name:            params.Name,
			IntervalSeconds: int64(params.Interval.Seconds()),
		})
	}
	if err != nil {
		if ctx.Err() == nil {
			log.Printf("[maintenance] take the turn for %s: %v", params.Name, err)
		}
		return false
	}
	return claimed > 0
}
