package v0_events

import (
	"context"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
)

// stillActive reports whether the account a stream belongs to may still sign
// in (#1909). A stream with no account behind it, as background principals and
// tests have, always may. A question the database cannot answer counts as no:
// the stream closes, and requireAuth decides when the app reconnects.
func stillActive(ctx context.Context, deps deputil.Dependencies, access accessutil.Access) bool {
	userID := access.Principal().UserID
	if userID == 0 {
		return true
	}
	database := deps.Database()
	if database == nil {
		return false
	}
	active, err := authutil.IsActive(ctx, database.Queries, userID)
	return err == nil && active
}
