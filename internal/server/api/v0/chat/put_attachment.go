package v0_chat

import (
	"net/http"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// putAttachment godoc
// @Summary Upload a chat attachment's ciphertext
// @Description Stores the raw body as an attachment's ciphertext. The id is 64 lowercase hex characters chosen by the client. The Quark does not see the file name, the media type or the key. Needs attach_files. A reader without it gets 403, and anyone without read_messages gets 404, delegated managers and admins included. A second upload of the same id is 409. The body may be at most 4 GiB, which is the server's disk cap. Nothing is published: the bytes are not a message until a later change binds them.
// @Tags chat
// @Accept application/octet-stream
// @Produce json
// @Param id path int true "Channel id"
// @Param attachmentId path string true "Attachment id, 64 lowercase hex characters"
// @Param body body string true "Ciphertext"
// @Success 201 {object} chatutil.PutAttachmentResult
// @Failure 400 {object} serverutil.Response "the attachment id is not 64 lowercase hex characters"
// @Failure 401 {object} serverutil.Response
// @Failure 403 {object} serverutil.Response "the caller reads the channel but lacks attach_files"
// @Failure 404 {object} serverutil.Response "no such channel, or the caller lacks read_messages"
// @Failure 409 {object} serverutil.Response "an attachment with this id already exists"
// @Failure 413 {object} serverutil.Response "ciphertext over 4 GiB"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/attachments/{attachmentId} [put]
func putAttachment(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	result, err := chatutil.PutAttachment(chatutil.PutAttachmentParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal,
		ChannelID: id, ID: c.Param("attachmentId"), DataDir: storageutil.GetDataDir(), Body: c.Request.Body,
	})
	if err != nil {
		return chatError(err)
	}
	return serverutil.NewResponse().WithStatusCode(http.StatusCreated).WithData(result)
}

var putAttachmentRoute = serverutil.ApiRoute("PUT", "/chat/channels/:id/attachments/:attachmentId", putAttachment)
