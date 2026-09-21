package main

import (
	"fmt"
	"os"

	"github.com/autobutler-org/quark/cmd/quark/install"
	"github.com/autobutler-org/quark/cmd/quark/serve"
	"github.com/autobutler-org/quark/cmd/quark/version"

	"github.com/spf13/cobra"
)

// @title						Quark API
// @version					v0
// @description				The REST API a Quark device serves to its Flutter clients. Every endpoint except
// @description				/auth/setup, /auth/login, /auth/recover, /auth/request-account and /auth/status needs a
// @description				session token. Sign in with POST /auth/login, then click Authorize and enter the word
// @description				Bearer, a space, and the token.
// @BasePath					/api/v0
// @securityDefinitions.apikey	BearerAuth
// @in							header
// @name						Authorization
// @description				A session token from POST /auth/login, entered as the word Bearer, a space, and the token.
// @security					BearerAuth
func main() {
	rootCmd := &cobra.Command{Use: "quark"}
	rootCmd.AddCommand(install.Cmd(), version.Cmd(), serve.Cmd())
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
