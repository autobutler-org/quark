package v0_version

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/versionutil"
	"github.com/gin-gonic/gin"
)

// getInstalledVersion godoc
// @Summary Get installed version
// @Description Retrieves the installed version of the application
// @Tags version
// @Produce json
// @Success 200 {object} VersionJSON
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /version [get]
func getInstalledVersion(c *gin.Context) *serverutil.Response {
	version := versionutil.GetVersion()

	return serverutil.Ok().WithData(VersionJSON{
		Semver:    version.Semver,
		GitCommit: version.GitCommit,
		GoVersion: version.GoVersion,
		BuildDate: version.BuildDate,
	})
}

var getInstalledVersionRoute = serverutil.ApiRoute(
	"GET", "/version", getInstalledVersion,
)
