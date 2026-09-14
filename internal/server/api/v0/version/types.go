package v0_version

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/updateutil"
)

// UpdateParams defines the parameters for updating to a specific version
type UpdateParams struct {
	Version string                   `json:"version"`
	Source  *updateutil.UpdateSource `json:"source,omitempty"`
	Force   bool                     `json:"force,omitempty"`
}

// VersionJSON is the JSON representation of the current version
type VersionJSON struct {
	Semver    string `json:"semver"`
	GitCommit string `json:"gitCommit"`
	GoVersion string `json:"goVersion"`
	BuildDate string `json:"buildDate"`
}

// SbomDependencyJSON is a single dependency in the software bill of materials
type SbomDependencyJSON struct {
	Path    string              `json:"path"`
	Version string              `json:"version"`
	Sum     string              `json:"sum,omitempty"`
	Replace *SbomDependencyJSON `json:"replace,omitempty"`
}

// SbomModuleJSON is the main module in the software bill of materials
type SbomModuleJSON struct {
	Path    string `json:"path"`
	Version string `json:"version"`
	Sum     string `json:"sum,omitempty"`
}

// SbomJSON is the full software bill of materials for the Go binary
type SbomJSON struct {
	GoVersion    string               `json:"goVersion"`
	Main         SbomModuleJSON       `json:"main"`
	Dependencies []SbomDependencyJSON `json:"dependencies"`
}

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		getInstalledVersionRoute,
		getSbomRoute,
		listVersionsRoute,
	}
}

// adminRouter holds the route that installs a version and restarts the Quark.
type adminRouter struct{}

func (r *adminRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		doUpdateRoute,
	}
}
