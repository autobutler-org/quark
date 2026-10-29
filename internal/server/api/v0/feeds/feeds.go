// Package v0_feeds serves /api/v0/feeds, each account's feed subscriptions
// (#3714). An account adds a feed by its URL, or by a site URL that is fetched
// and searched for a feed link. Subscriptions are per account and not shared:
// another account's feed, an admin's request included, reads as not found. A
// feed URL can carry a private token, so errors and events never repeat it.
// None of the routes are admin-only. Entries are not read here.
package v0_feeds

import "github.com/autobutler-org/quark/pkg/util/serverutil"

// NewRouter returns the router for /api/v0/feeds.
func NewRouter() serverutil.Router {
	return &router{}
}
