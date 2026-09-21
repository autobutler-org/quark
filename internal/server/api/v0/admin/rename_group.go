package v0_admin

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// renameGroup godoc
// @Summary Rename a group
// @Description Renames a group under the same rules a new name follows; a group may take its own name in another case. Its folder in groups is renamed to match as an ordinary move does, carrying its shares, favorites and album items, and publishing move and access_changed. The everyone group can't be renamed. The response lists no members. Publishes account_changed. Admin-only.
// @Tags admin
// @Accept json
// @Produce json
// @Param id path int true "Group id"
// @Param body body groupNameBody true "The group's new name"
// @Success 200 {object} grouputil.Group
// @Failure 400 {object} serverutil.Response "invalid name, or the everyone group"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no group has that id"
// @Failure 409 {object} serverutil.Response "a group with that name already exists, or another folder in groups already has the new name"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/groups/{id} [put]
func renameGroup(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	groupID, err := idParam(c, "id", grouputil.ErrGroupNotFound)
	if err != nil {
		return groupErrorResponse(err)
	}
	var body groupNameBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(grouputil.ErrInvalidGroupName)
	}

	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := grouputil.RenameGroup(c.Request.Context(), grouputil.RenameGroupParams{
		Database: database,
		Registry: deps.VFSRegistry(),
		Storage:  deps.StorageService(),
		EventBus: deps.EventBus(),
		FilesDir: filesDir,
		GroupID:  groupID,
		Name:     body.Name,
	})
	if err != nil {
		return groupErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
	return serverutil.Ok().WithData(result.Group)
}

var renameGroupRoute = serverutil.ApiRoute("PUT", "/admin/groups/:id", renameGroup)
