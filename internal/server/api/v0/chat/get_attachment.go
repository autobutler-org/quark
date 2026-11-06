package v0_chat

import (
	"net/http"
	"time"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/gin-gonic/gin"
)

// getAttachment godoc
// @Summary Download a chat attachment's ciphertext
// @Description Serves the ciphertext, honoring HTTP range requests. An attachment no message is bound to is readable by its uploader only; anyone else gets 404, so the answer does not reveal that the id exists. A bound attachment needs read_messages, and anyone without it gets 404, delegated managers and admins included. The response is not cached.
// @Tags chat
// @Produce application/octet-stream
// @Param id path int true "Channel id"
// @Param attachmentId path string true "Attachment id, 64 lowercase hex characters"
// @Success 200 {file} file "the ciphertext"
// @Success 206 {file} file "a byte range of the ciphertext"
// @Failure 400 {object} serverutil.Response "the attachment id is not 64 lowercase hex characters"
// @Failure 401 {object} serverutil.Response
// @Failure 404 {object} serverutil.Response "no such attachment, or the caller may not read it"
// @Failure 500 {object} serverutil.Response
// @Security BearerAuth
// @Router /chat/channels/{id}/attachments/{attachmentId} [get]
func getAttachment(c *gin.Context) *serverutil.Response {
	deps, principal, failed := callerContext(c)
	if failed != nil {
		return failed
	}
	id, failed := channelID(c)
	if failed != nil {
		return failed
	}
	opened, err := chatutil.OpenAttachment(chatutil.OpenAttachmentParams{
		Ctx: c.Request.Context(), Database: deps.Database(), Principal: principal,
		ChannelID: id, ID: c.Param("attachmentId"), DataDir: storageutil.GetDataDir(),
	})
	if err != nil {
		return chatError(err)
	}
	defer opened.File.Close()
	c.Header("Content-Type", "application/octet-stream")
	c.Header("Accept-Ranges", "bytes")
	c.Header("Cache-Control", "private, no-store")
	http.ServeContent(c.Writer, c.Request, "attachment.bin", time.Time{}, opened.File)
	return nil
}

var getAttachmentRoute = serverutil.ApiRoute("GET", "/chat/channels/:id/attachments/:attachmentId", getAttachment)
