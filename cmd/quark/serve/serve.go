// Package serve is the quark serve subcommand: it builds the default dependency graph and starts the HTTP server,
// over plain HTTP when --insecure is set.
package serve

import (
	"fmt"
	"os"

	"github.com/autobutler-org/quark/internal/server"
	"github.com/autobutler-org/quark/pkg/util/deputil"

	"github.com/spf13/cobra"
)

func Cmd() *cobra.Command {
	var insecure bool

	cmd := &cobra.Command{
		Use:   "serve",
		Short: "Start the Quark server",
		Long:  `The serve command starts the Quark server, allowing you to interact with the Quark system through its API.`,
		RunE: func(cmd *cobra.Command, args []string) error {
			// QUARK_INSECURE=true is equivalent to --insecure, useful for
			// Makefile targets and CI without modifying command-line args.
			if !insecure && os.Getenv("QUARK_INSECURE") == "true" {
				insecure = true
			}
			fmt.Println("Starting Quark server...")
			deps, err := deputil.DefaultDependencies()
			if err != nil {
				return fmt.Errorf("failed to initialize dependencies: %w", err)
			}
			if err := server.StartServer(deps, server.StartOptions{Insecure: insecure}); err != nil {
				return fmt.Errorf("failed to start server: %w", err)
			}
			return nil
		},
	}

	cmd.Flags().BoolVar(&insecure, "insecure", false, "Disable TLS and serve over plain HTTP (for local development only). Also enabled via QUARK_INSECURE=true env var.")

	return cmd
}
