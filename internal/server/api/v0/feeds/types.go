package v0_feeds

import (
	"github.com/autobutler-org/quark/pkg/util/feedutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		addFeedRoute,
		listFeedsRoute,
		getFeedRoute,
		updateFeedRoute,
		deleteFeedRoute,
	}
}

// addRequest is the body of POST /feeds. discover asks for a site page rather
// than a feed URL.
type addRequest struct {
	URL      string `json:"url"`
	Name     string `json:"name"`
	Folder   string `json:"folder"`
	Discover bool   `json:"discover"`
}

// updateRequest is the body of PATCH /feeds/{id}. A missing field is left as
// it is. An empty string clears the name or moves the feed out of its folder.
type updateRequest struct {
	Name   *string `json:"name"`
	Folder *string `json:"folder"`
}

// ChoiceJSON is the 409 body when a site offers several feeds. The caller
// subscribes to one of Candidates by its URL.
type ChoiceJSON struct {
	Error      string               `json:"error"`
	Candidates []feedutil.Candidate `json:"candidates"`
}
