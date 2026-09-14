package v0_jobs

import (
	"fmt"
	"strconv"

	"github.com/gin-gonic/gin"
)

// parseJobID reads the :id path parameter.
func parseJobID(c *gin.Context) (int64, error) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		return 0, fmt.Errorf("invalid job id %q", c.Param("id"))
	}
	return id, nil
}
