package v0_events

import (
	"context"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
)

// stillActive reports whether the account a stream belongs to may still sign
// in (#1909), with the admin role it connected with (#1910): a demoted admin's
// stream would otherwise stay unfiltered, and a promoted account's would stay
// filtered. A stream with no account behind it, as background principals and
// tests have, always may. A question the database cannot answer counts as no:
// the stream closes, and requireAuth decides when the app reconnects.
func stillActive(ctx context.Context, deps deputil.Dependencies, access accessutil.Access) bool {
	principal := access.Principal()
	userID := principal.UserID
	if userID == 0 {
		return true
	}
	database := deps.Database()
	if database == nil {
		return false
	}
	active, err := authutil.IsActiveAs(ctx, database.Queries, userID, principal.IsAdmin)
	return err == nil && active
}
