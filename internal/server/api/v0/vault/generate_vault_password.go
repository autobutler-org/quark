package v0_vault

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// generateVaultPassword godoc
// @Summary Generate a password
// @Description Returns a random password. An absent or unparsable body falls back to 20 characters of every class.
// @Tags vault
// @Accept json
// @Produce json
// @Param body body generateRequest false "Generator options"
// @Success 200 {object} object "generated password"
// @Failure 400 {object} serverutil.Response "Bad Request"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/generate [post]
func generateVaultPassword(c *gin.Context) *serverutil.Response {
	var req generateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		// Defaults if no body provided.
		req = generateRequest{
			Length:    20,
			Uppercase: true,
			Lowercase: true,
			Digits:    true,
			Symbols:   true,
		}
	}

	result, err := vaultutil.GeneratePassword(vaultutil.GeneratePasswordParams{
		Length:         req.Length,
		Uppercase:      req.Uppercase,
		Lowercase:      req.Lowercase,
		Digits:         req.Digits,
		Symbols:        req.Symbols,
		AvoidAmbiguous: req.AvoidAmbiguous,
	})
	if errors.Is(err, vaultutil.ErrEmptyCharset) {
		return serverutil.BadRequest(err)
	}
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"password": result.Password,
	})
}

var generateVaultPasswordRoute = serverutil.ApiRoute("POST", "/vault/generate", generateVaultPassword)
