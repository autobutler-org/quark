package v0_settings

import (
	"github.com/autobutler-org/quark/pkg/util/featureflagutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// listFeatures godoc
// @Summary List the beta feature flags
// @Description Returns every registered beta feature flag with its admin-facing label and description, its default, the release or issue it was introduced in, the issue that will remove it, and whether it is on now. Open to any signed-in user, so the app can hide a feature that is off.
// @Tags settings
// @Produce json
// @Success 200 {object} featureflagutil.ListFlagsResult
// @Failure 401 {object} serverutil.Response
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/features [get]
func listFeatures(_ *gin.Context) *serverutil.Response {
	result, err := featureflagutil.ListFlags(featureflagutil.ListFlagsParams{})
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	return serverutil.Ok().WithData(result)
}

var listFeaturesRoute = serverutil.ApiRoute("GET", "/settings/features", listFeatures)
