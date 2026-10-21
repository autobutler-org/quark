package v0_previews

import (
	"errors"
	"time"

	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		previewDocumentRoute,
		previewSlidesRoute,
		getPartRoute,
		getPropertiesRoute,
	}
}

// previewDeadline bounds one conversion, so a hostile document costs one
// failed request rather than a parser that runs until the client gives up.
const previewDeadline = 30 * time.Second

// errNoAccess is what a caller hears about a document they may not read: the
// same as one that does not exist.
var errNoAccess = errors.New("file not found")

// streamWriter writes a streamed response, setting its Content-Type only
// when the first byte goes out. A conversion that fails before then answers
// with an ordinary JSON error instead.
type streamWriter struct {
	c           *gin.Context
	contentType string
}

func (w streamWriter) Write(p []byte) (int, error) {
	if !w.c.Writer.Written() {
		w.c.Header("Content-Type", w.contentType)
		w.c.Header("X-Content-Type-Options", "nosniff")
	}
	return w.c.Writer.Write(p)
}
