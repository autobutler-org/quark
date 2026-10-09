// Command quark is the Quark binary: quark serve runs the API and the embedded web app, quark install sets it up as
// a system service, quark auth-key derives the key a script signs in with, and quark version reports the build.
package main

import (
	"fmt"
	"os"

	"github.com/autobutler-org/quark/cmd/quark/authkey"
	"github.com/autobutler-org/quark/cmd/quark/install"
	"github.com/autobutler-org/quark/cmd/quark/serve"
	"github.com/autobutler-org/quark/cmd/quark/version"

	"github.com/spf13/cobra"
)

// @title						Quark API
// @version					v0
// @description				The REST API a Quark device serves to its Flutter clients. Every endpoint except
// @description				/auth/setup, /auth/login, /auth/salt, /auth/recover, /auth/recover/keys,
// @description				/auth/request-account and /auth/status needs a session token. Sign in with POST /auth/login,
// @description				then click Authorize and enter the word Bearer, a space, and the token. Login takes the auth
// @description				key a client derives from the password and the salt GET /auth/salt returns; the password
// @description				alone is refused with 426 (#2430). A script gets that key from quark auth-key,
// @description				given this Quark's address as --host and the username as -u (#2713).
// @BasePath					/api/v0
// @securityDefinitions.apikey	BearerAuth
// @in							header
// @name						Authorization
// @description				A session token from POST /auth/login, entered as the word Bearer, a space, and the token.
// @security					BearerAuth
func main() {
	// Errors go to stderr, once, so $(quark auth-key ...) never captures one.
	rootCmd := &cobra.Command{Use: "quark", SilenceErrors: true}
	rootCmd.AddCommand(install.Cmd(), version.Cmd(), serve.Cmd(), authkey.Cmd())
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}
