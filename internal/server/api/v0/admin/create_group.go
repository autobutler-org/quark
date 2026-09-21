package v0_admin

import (
	"errors"
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/grouputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// createGroup godoc
// @Summary Create a group
// @Description Creates an empty group and its folder in groups on the internal device, named after the group, with one grant giving the group write there; an existing folder of that name is adopted. The name is trimmed, has 1 to 64 characters, no control characters or slashes, isn't . or .., and is unique ignoring case. Publishes account_changed and new_folder. Admin-only.
// @Tags admin
// @Accept json
// @Produce json
// @Param body body groupNameBody true "The group's name"
// @Success 201 {object} grouputil.Group
// @Failure 400 {object} serverutil.Response "invalid name"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response
// @Failure 409 {object} serverutil.Response "a group with that name already exists"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /admin/groups [post]
func createGroup(c *gin.Context) *serverutil.Response {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return serverutil.InternalServerError(nil)
	}
	database := deps.Database()
	if database == nil {
		return serverutil.InternalServerError(errors.New("database unavailable"))
	}
	var body groupNameBody
	if err := c.ShouldBindJSON(&body); err != nil {
		return serverutil.BadRequest(grouputil.ErrInvalidGroupName)
	}

	filesDir, err := storageutil.GetFilesDir()
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	result, err := grouputil.CreateGroup(c.Request.Context(), grouputil.CreateGroupParams{
		Database: database,
		FilesDir: filesDir,
		Name:     body.Name,
	})
	if err != nil {
		return groupErrorResponse(err)
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
		bus.Publish(eventbus.Event{Kind: eventbus.EventNewFolder, Path: result.FolderPath})
	}
	return serverutil.Ok().WithStatusCode(http.StatusCreated).WithData(result.Group)
}

var createGroupRoute = serverutil.ApiRoute("POST", "/admin/groups", createGroup)
