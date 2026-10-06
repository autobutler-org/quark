package v0_events

import (
	"context"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
)

// reload returns a stream's access as of the event with sequence number seq,
// and false when the stream must close: its account was turned off or
// deleted (#1909), its admin role changed since it connected (#1910), or the
// answer could not be had. A demoted admin's stream would otherwise stay
// unfiltered, and a promoted account's would stay filtered; a failed load
// closes rather than filter against a stale snapshot, and requireAuth decides
// when the app reconnects.
//
// Every stream of the account shares one load per change through the access
// cache (#2764). A stream with no account behind it, as background principals
// and tests have, keeps what it has.
func reload(ctx context.Context, deps deputil.Dependencies, access accessutil.Access, seq uint64) (accessutil.Access, bool) {
	principal := access.Principal()
	if principal.UserID == 0 {
		return access, true
	}
	cache := deps.AccessCache()
	if cache == nil {
		return access, false
	}
	result, err := cache.Get(accessutil.CacheGetParams{
		Ctx:      ctx,
		Database: deps.Database(),
		Storage:  deps.StorageService(),
		Bus:      deps.EventBus(),
		UserID:   principal.UserID,
		Seq:      seq,
	})
	if err != nil || !result.Active || result.Access.Principal().IsAdmin != principal.IsAdmin {
		return access, false
	}
	return result.Access, true
}
