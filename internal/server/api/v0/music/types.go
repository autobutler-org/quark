package v0_music

import (
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listTracksRoute,
		listAlbumsRoute,
		listArtistsRoute,
		listGenresRoute,
		searchMusicRoute,
		getStatusRoute,
		recordPlayRoute,
		listHistoryRoute,
	}
}

// adminRouter holds the route that queues a library scan.
type adminRouter struct{}

func (r *adminRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		rescanLibraryRoute,
	}
}

// caller is what every music route needs: the dependencies and what the
// caller may read.
type caller struct {
	deps   deputil.Dependencies
	access accessutil.Access
}

// recordPlayRequest names the track a play is recorded for.
type recordPlayRequest struct {
	// Serial is the device holding the track, '' for the internal drive.
	Serial  string `json:"serial"`
	RelPath string `json:"relPath" binding:"required"`
}
