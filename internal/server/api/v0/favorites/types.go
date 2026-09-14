package v0_favorites

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// errNoAccess is what a caller hears about a photo they may not see. It reads
// the same as a photo that does not exist, because to them it does not.
var errNoAccess = errors.New("photo not found")

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		toggleFavoriteRoute,
		isFavoriteRoute,
		listFavoritesRoute,
	}
}

type favoriteRequest struct {
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
}

type favoriteResponse struct {
	IsFavorite bool `json:"isFavorite"`
}

type favoriteItemJSON struct {
	DeviceSerial string `json:"deviceSerial"`
	RelPath      string `json:"relPath"`
	CreatedAt    string `json:"createdAt"`
}
