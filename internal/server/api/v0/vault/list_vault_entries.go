package v0_vault

import (
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
	"github.com/gin-gonic/gin"
)

// listVaultEntries godoc
// @Summary List vault entries
// @Description Returns every entry's clear-text metadata. Passwords and notes stay encrypted; read one entry to decrypt it.
// @Tags vault
// @Produce json
// @Success 200 {object} object "entries: array of vaultutil.EntryListItem"
// @Failure 500 {object} serverutil.Response "Internal Server Error"
// @Security BearerAuth
// @Router /vault/entries [get]
func listVaultEntries(c *gin.Context) *serverutil.Response {
	deps, errResp := getDeps(c)
	if errResp != nil {
		return errResp
	}

	result, err := vaultutil.ListEntries(c.Request.Context(), vaultutil.ListEntriesParams{
		Queries: deps.VaultDB().Queries,
	})
	if err != nil {
		return serverutil.InternalServerError(err)
	}

	return serverutil.Ok().WithContentType(serverutil.ContentTypeJSON).WithData(gin.H{
		"entries": result.Entries,
	})
}

var listVaultEntriesRoute = serverutil.ApiRoute("GET", "/vault/entries", listVaultEntries)
