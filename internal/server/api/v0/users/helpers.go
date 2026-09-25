package v0_users

import (
	"errors"
	"fmt"
	"io"

	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/gin-gonic/gin"
)

// callerID returns the signed-in user's id, or an error when requireAuth set
// none.
func callerID(c *gin.Context) (int64, error) {
	userID, ok := ctxutil.Get[int64](c, "userID")
	if !ok || userID == 0 {
		return 0, errors.New("authentication required")
	}
	return userID, nil
}

// publishAccountChanged tells open clients to refetch the account, and with
// it the picture's version.
func publishAccountChanged(c *gin.Context) {
	deps, ok := ctxutil.Get[deputil.Dependencies](c, "deps")
	if !ok {
		return
	}
	if bus := deps.EventBus(); bus != nil {
		bus.Publish(eventbus.Event{Kind: eventbus.EventAccountChanged})
	}
}

// filePart returns the stream of the multipart field "file", read straight
// off the request body rather than parsed into memory or a temporary file.
func filePart(c *gin.Context) (io.ReadCloser, error) {
	reader, err := c.Request.MultipartReader()
	if err != nil {
		return nil, fmt.Errorf("expected a multipart upload: %w", err)
	}
	for {
		part, err := reader.NextPart()
		if err == io.EOF {
			return nil, errors.New(`no "file" field in the upload`)
		}
		if err != nil {
			return nil, fmt.Errorf("read upload: %w", err)
		}
		if part.FormName() == "file" {
			return part, nil
		}
		part.Close()
	}
}
