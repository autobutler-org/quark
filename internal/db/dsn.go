package db

import "strings"

// connectionParams carries every setting a Quark database connection is
// required to be opened with. All of them are per-connection state that the
// driver applies at open, which is why they belong in the DSN rather than in an
// Exec: database/sql hands out connections from a pool and opens new ones on
// demand, so a pragma issued through Exec arms whichever connection happened to
// serve that call and leaves the rest of the pool — and every connection opened
// later — without it.
//
// _time_format=datetime and _timezone=UTC make the driver store every time.Time
// as SQLite's own canonical UTC format ("YYYY-MM-DD HH:MM:SS", format 3), which
// is exactly what datetime('now') produces. Both halves are required, and
// neither is sufficient alone (#1650):
//
//   - _timezone=UTC converts the value to UTC before it is formatted. Without
//     it, format 3 writes local wall-clock time and silently discards the
//     offset, which is worse than the bug it replaces — the value reads back
//     as a UTC instant hours away from the one that was written.
//   - _time_format=datetime picks format 3. Without it the driver writes Go's
//     t.String() ("2026-08-28 16:04:23.848055 -0700 PDT m=+3600.0"), which no
//     SQLite date function can parse and which sorts wrongly against
//     datetime('now').
//
// This is also why neither is left to a .UTC() call at each write site: queries
// compare these columns as text, so a single write site that forgot would
// silently reintroduce the bug.
//
// _pragma=busy_timeout(5000) makes a connection that finds the database locked
// retry for five seconds instead of failing at once. SQLite allows one writer
// at a time and returns SQLITE_BUSY to everyone else the instant they collide;
// with no busy handler installed, an ordinary background write — trackDevice's
// connected_devices upsert, say — turned any concurrent read into an error.
// requireAuth cannot tell that error from a bad token, so a request that
// happened to land during a write got a 401 and the client was logged out
// (it also made TestRequireAuth_SetsUserIDOnContext flaky in CI).
//
// _foreign_keys=on enforces the references the schema already declares. SQLite
// parses REFERENCES clauses whether or not enforcement is on and simply ignores
// them when it is off, so every ON DELETE CASCADE in the migration set — a
// user's sessions, an album's items and its child albums, a vault folder's
// subfolders — was documentation rather than behavior. With it on, those
// cascades run and an insert naming a parent that does not exist fails instead
// of creating an orphan.
const connectionParams = "_time_format=datetime&_timezone=UTC&_foreign_keys=on&_pragma=busy_timeout(5000)"

// DSN returns the connection string for a SQLite database at path, carrying the
// settings every Quark database is expected to be opened with. Any database
// this codebase writes must be opened through this, including from tests — a
// connection that skips it writes a timestamp format the queries misread and
// silently accepts rows the schema forbids.
func DSN(path string) string {
	sep := "?"
	if strings.Contains(path, "?") {
		sep = "&"
	}
	return path + sep + connectionParams
}
