package v0_versions

import "github.com/autobutler-org/quark/pkg/util/serverutil"

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		createVersionRoute,
		deleteVersionRoute,
		getVersionContentRoute,
		listVersionsRoute,
		restoreVersionRoute,
	}
}

// createVersionRequest asks for a snapshot of the file at Path.
type createVersionRequest struct {
	// Path is the file, files-relative.
	Path string `json:"path" binding:"required"`
	// Kind is "named" (the default) or "auto".
	Kind string `json:"kind"`
	// Label names a named version, and is required for one.
	Label string `json:"label"`
}
