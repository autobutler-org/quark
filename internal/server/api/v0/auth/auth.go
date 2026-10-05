// Package v0_auth serves /api/v0/auth: first-boot setup, login and logout, account recovery, requests for an
// account, the salt a client derives its auth key with, the caller's recovery key, and the caller's sessions and
// account. Setup, login, salt, recover, recover/keys, request-account and status are exempt from the session check.
// A raw password or recovery phrase is taken only to move a legacy account to keys, once each: the password beside
// an authKey at login, and the phrase at recover/keys and, beside both new keys, at recover. Any other body shaped
// like an app from before auth keys gets 426 (#2430).
package v0_auth

import "github.com/autobutler-org/quark/pkg/util/serverutil"

func NewRouter() serverutil.Router {
	return &router{}
}
