// Package bundle is the quark bundle subcommand: export writes a bundle of this install, its database rows and its
// files, and import starts a new, uninitialized install from one, on either database backend (#3838).
package bundle

import (
	"errors"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/bundleutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/spf13/cobra"
)

func Cmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "bundle",
		Short: "Move a whole Quark to a new install: its accounts, data and files",
		Long: `A bundle is one tar file holding an install's database rows and its files. Take it with
quark bundle export on the source and start a new, uninitialized install from it with quark bundle import.
Either side may run on SQLite or on PostgreSQL.`,
	}
	cmd.AddCommand(exportCmd(), importCmd())
	return cmd
}

// databaseFlags adds --database-url and --data-dir, and returns a function
// that reads the database the command works on: PostgreSQL when a URL is
// given, otherwise whatever the environment names, as the server reads it.
func databaseFlags(cmd *cobra.Command, dataDir *string) func() (db.Config, error) {
	var databaseURL string
	// The default is read when the command runs, not given here: the help would print it, password and all.
	cmd.Flags().StringVar(&databaseURL, "database-url", "",
		"the install's PostgreSQL database; leave it out on SQLite (default $"+db.DatabaseURLEnv+" when $"+
			db.BackendEnv+"=postgres)")
	cmd.Flags().StringVar(dataDir, "data-dir", storageutil.GetDataDir(), "the install's data directory")
	return func() (db.Config, error) {
		if databaseURL != "" {
			return db.Config{Backend: db.Postgres, PostgresURL: databaseURL}, nil
		}
		return db.ConfigFromEnv()
	}
}

func exportCmd() *cobra.Command {
	var out, dataDir string
	cmd := &cobra.Command{
		Use:   "export",
		Short: "Write a bundle of this install",
		Long: `export writes this install's database rows and files to one tar file. It only reads the install.

Stop the service first (sudo systemctl stop quark) so the rows and the files agree, and run this as the user
it runs as (sudo -u quark ...), so the default --data-dir is its data directory. On PostgreSQL, pass the
URL the service uses as --database-url.`,
		Example: `  sudo systemctl stop quark
  sudo -u quark quark bundle export -o /tmp/quark-bundle.tar
  sudo -u quark quark bundle export -o /tmp/quark-bundle.tar --database-url 'postgres://quark:secret@db:5432/quark'`,
		Args:         cobra.NoArgs,
		SilenceUsage: true,
	}
	config := databaseFlags(cmd, &dataDir)
	cmd.Flags().StringVarP(&out, "out", "o", "quark-bundle.tar", "the bundle to write; it must not exist")
	cmd.RunE = func(cmd *cobra.Command, _ []string) error {
		database, err := config()
		if err != nil {
			return err
		}
		f, err := os.OpenFile(out, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if err != nil {
			return fmt.Errorf("%w. Remove it or pass another file with -o", err)
		}
		result, err := bundleutil.Export(cmd.Context(), bundleutil.ExportParams{DataDir: dataDir, Database: database, Out: f})
		if err = errors.Join(err, f.Close()); err != nil {
			_ = os.Remove(out)
			return fmt.Errorf("%w\nNothing on the install was changed", err)
		}
		printSummary(os.Stdout, "Wrote", result.Database, result.Files, result.Bytes)
		fmt.Printf("\nThe bundle is %s. Copy it to the new install and run quark bundle import there.\n", out)
		return nil
	}
	return cmd
}

func importCmd() *cobra.Command {
	var dataDir string
	cmd := &cobra.Command{
		Use:   "import <bundle.tar>",
		Short: "Start this new, uninitialized install from a bundle",
		Long: `import fills this install from a bundle quark bundle export wrote: the files go into the data
directory and the rows into the database the install runs on. The install must be new: one whose database
has no account yet. One with an account is refused, and nothing on it is changed.

Stop the service first and run this as the user it runs as, so the files are theirs. On PostgreSQL, pass the
URL the service will use as --database-url. A failed or interrupted import leaves the install without
accounts, so running it again is safe.`,
		Example: `  sudo systemctl stop quark
  sudo -u quark quark bundle import /tmp/quark-bundle.tar
  sudo -u quark quark bundle import /tmp/quark-bundle.tar --database-url 'postgres://quark:secret@db:5432/quark'`,
		Args: func(cmd *cobra.Command, args []string) error {
			if len(args) != 1 {
				_ = cmd.Usage()
				return errors.New("name the bundle to import, the file quark bundle export wrote")
			}
			return nil
		},
		SilenceUsage: true,
	}
	config := databaseFlags(cmd, &dataDir)
	cmd.RunE = func(cmd *cobra.Command, args []string) error {
		database, err := config()
		if err != nil {
			return err
		}
		f, err := os.Open(args[0])
		if err != nil {
			return fmt.Errorf("%w. Pass the file quark bundle export wrote", err)
		}
		defer f.Close()
		result, err := bundleutil.Import(cmd.Context(), bundleutil.ImportParams{DataDir: dataDir, Database: database, Bundle: f})
		if err != nil {
			return fmt.Errorf("%w\nThe install has no accounts yet, so running this again is safe", err)
		}
		printSummary(os.Stdout, "Imported", result.Database, result.Files, result.Bytes)
		if database.Backend == db.Postgres {
			fmt.Printf(`
If the service is not already on PostgreSQL, run sudo systemctl edit quark and add

  [Service]
  Environment="%s=%s"
  Environment="%s=<the URL you passed>"

`, db.BackendEnv, db.Postgres, db.DatabaseURLEnv)
		}
		fmt.Println("\nStart the service with sudo systemctl start quark and sign in with an account from the bundle.")
		return nil
	}
	return cmd
}

// printSummary prints each table's row count, and what the counts prove: the
// copied tables match their source, and the rebuilt ones were left empty.
func printSummary(w io.Writer, verb string, result db.CopyDatabaseResult, files, bytes int64) {
	var total, rebuilt int64
	for _, table := range result.Tables {
		_, _ = fmt.Fprintf(w, "  %-28s %8d\n", table.Table, table.Rows)
		total += table.Rows
		if table.Rebuilt {
			rebuilt++
		}
	}
	_, _ = fmt.Fprintf(w, "%s %d rows in %d tables in %s; every copied table matches its row count in the source.\n",
		verb, total, int64(len(result.Tables))-rebuilt, result.Elapsed.Round(time.Millisecond))
	_, _ = fmt.Fprintf(w, "%s %d files, %d bytes.\n", verb, files, bytes)
	if rebuilt > 0 {
		_, _ = fmt.Fprintln(w, "Content search was left empty: the server rebuilds it from the files when it starts.")
	}
}
