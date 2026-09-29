package v0_settings

import (
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/featureflagutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
)

// updateFeature godoc
// @Summary Turn a beta feature flag on or off
// @Description Sets whether the beta feature named by key is on for everyone on the Quark, and publishes feature_flag_changed. Turning a feature off hides it; nothing it stored is deleted. A key the registry does not declare, including a retired flag's, is 404. Admin-only.
// @Tags settings
// @Accept json
// @Produce json
// @Param key path string true "Feature flag key"
// @Param body body featureSetting true "Whether the feature is on"
// @Success 200 {object} featureflagutil.FlagState
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "unknown feature flag"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /settings/features/{key} [put]
func updateFeature(c *gin.Context) *serverutil.Response {
	var body featureSetting
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(fmt.Errorf("invalid request body: %w", err))
	}
	result, err := featureflagutil.SetFlag(featureflagutil.SetFlagParams{Key: c.Param("key"), Enabled: *body.Enabled})
	if errors.Is(err, featureflagutil.ErrUnknownFlag) {
		return serverutil.NotFound(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}
	if deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps"); ok && deps.EventBus() != nil {
		deps.EventBus().Publish(eventbus.Event{Kind: eventbus.EventFeatureFlagChanged})
	}
	return serverutil.Ok().WithData(result.Feature)
}

var updateFeatureRoute = serverutil.ApiRoute("PUT", "/settings/features/:key", updateFeature)
