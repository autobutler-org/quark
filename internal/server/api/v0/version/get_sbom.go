package v0_version

import (
	"runtime/debug"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// getSbom godoc
// @Summary Get software bill of materials
// @Description Returns the Go version and all embedded dependency information from the compiled binary
// @Tags version
// @Produce json
// @Success 200 {object} SbomJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /sbom [get]
func getSbom(c *gin.Context) *serverutil.Response {
	info, ok := debug.ReadBuildInfo()
	if !ok {
		return serverutil.InternalServerError(nil)
	}

	deps := make([]SbomDependencyJSON, 0, len(info.Deps))
	for _, dep := range info.Deps {
		entry := SbomDependencyJSON{
			Path:    dep.Path,
			Version: dep.Version,
			Sum:     dep.Sum,
		}
		if dep.Replace != nil {
			replaced := SbomDependencyJSON{
				Path:    dep.Replace.Path,
				Version: dep.Replace.Version,
				Sum:     dep.Replace.Sum,
			}
			entry.Replace = &replaced
		}
		deps = append(deps, entry)
	}

	return serverutil.Ok().WithData(SbomJSON{
		GoVersion: info.GoVersion,
		Main: SbomModuleJSON{
			Path:    info.Main.Path,
			Version: info.Main.Version,
			Sum:     info.Main.Sum,
		},
		Dependencies: deps,
	})
}

var getSbomRoute = serverutil.ApiRoute(
	"GET", "/sbom", getSbom,
)
