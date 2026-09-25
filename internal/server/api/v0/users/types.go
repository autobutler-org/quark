package v0_users

import "github.com/autobutler-org/quark/pkg/util/serverutil"

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		setAvatarRoute,
		deleteAvatarRoute,
		getAvatarRoute,
	}
}
