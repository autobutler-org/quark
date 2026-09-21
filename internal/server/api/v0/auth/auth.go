// Package v0_auth serves /api/v0/auth: first-boot setup, login and logout, account recovery, requests for an
// account, and the caller's sessions and account. Setup, login, recover, request-account and status are exempt
// from the session check.
package v0_auth

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
