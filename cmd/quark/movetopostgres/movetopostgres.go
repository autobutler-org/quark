// Package movetopostgres is the quark move-to-postgres subcommand, which copies an install's SQLite database
// into an empty PostgreSQL one through db.MoveToPostgres (#2962).
package movetopostgres

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"

	"github.com/spf13/cobra"
)

func Cmd() *cobra.Command {
	var databaseURL, sqlitePath string
	cmd := &cobra.Command{
		Use:   "move-to-postgres",
		Short: "Copy this install's SQLite database into an empty PostgreSQL database",
		Long: `move-to-postgres copies every table of the SQLite database into an empty PostgreSQL database, in one
transaction, and checks that every table holds as many rows as it did in SQLite.

Stop the service first (sudo systemctl stop quark) and run this as the user it runs as
(sudo -u quark quark move-to-postgres ...), so the default --sqlite is its database. Rows written while
the copy runs would not be moved.

The SQLite file is opened read-only and never changed. A failed or interrupted run leaves nothing in
PostgreSQL, and running it again is safe. Until the service is told to use PostgreSQL it starts on SQLite
as before, so abandoning the move is a matter of not switching.

Moving from PostgreSQL back to SQLite is not supported.`,
		Example: `  sudo systemctl stop quark
  sudo -u quark quark move-to-postgres --database-url 'postgres://quark:secret@db.example:5432/quark'`,
		Args:         cobra.NoArgs,
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			if databaseURL == "" {
				databaseURL = os.Getenv(db.DatabaseURLEnv)
			}
			if databaseURL == "" {
				_ = cmd.Usage()
				return errors.New("no PostgreSQL database to move to: pass --database-url postgres://user:password@host:5432/quark, or set " + db.DatabaseURLEnv)
			}
			fmt.Printf("Moving %s to PostgreSQL. This keeps the SQLite file as it is.\n", sqlitePath)
			result, err := db.MoveToPostgres(cmd.Context(), db.MoveToPostgresParams{SQLitePath: sqlitePath, PostgresURL: databaseURL})
			if err != nil {
				return fmt.Errorf("%w\nThe install still runs on SQLite, unchanged", err)
			}
			var total int64
			for _, table := range result.Tables {
				note := ""
				if table.Rebuilt {
					note = "  (rebuilt from the files when the server starts)"
				}
				fmt.Printf("  %-28s %8d%s\n", table.Table, table.Rows, note)
				total += table.Rows
			}
			fmt.Printf("Moved %d rows in %d tables in %s; every count matches SQLite's.\n",
				total, len(result.Tables), result.Elapsed.Round(time.Millisecond))
			fmt.Printf(`
Next, point the service at PostgreSQL. Run sudo systemctl edit quark, add

  [Service]
  Environment="%s=%s"
  Environment="%s=<the URL you passed>"

and start it with sudo systemctl start quark. To abandon the move, start it without those lines: it runs on
SQLite as before.
`, db.BackendEnv, db.Postgres, db.DatabaseURLEnv)
			return nil
		},
	}
	// The default is read in RunE, not given here: the help would print it, password and all.
	cmd.Flags().StringVar(&databaseURL, "database-url", "",
		"the empty PostgreSQL database to fill (default $"+db.DatabaseURLEnv+")")
	cmd.Flags().StringVar(&sqlitePath, "sqlite", filepath.Join(storageutil.GetDataDir(), "quark.db"),
		"the install's SQLite database")
	return cmd
}
