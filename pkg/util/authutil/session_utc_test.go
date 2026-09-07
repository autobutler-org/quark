package authutil_test

import (
	"context"
	"database/sql"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	_ "modernc.org/sqlite"
)

// Session expiry compared in the wrong zone (#1650). expires_at was written in
// local time but compared against datetime('now'), which is UTC, so the
// comparison was wrong by the server's UTC offset: west of UTC a session
// expired early, east of it a session outlived its expiry.
//
// The window is only ever as wide as the offset, so these tests are meaningless
// in UTC — each one pins time.Local to a fixed non-UTC zone rather than
// inheriting whatever the machine happens to be set to. CI runs in UTC and
// would otherwise pass no matter what the code does.

// inZone pins time.Local for the duration of a test. Not parallel-safe: the
// clock and the local zone are both package-level state.
//
// A real IANA zone, not time.FixedZone: the pre-fix storage format is Go's
// t.String(), which embeds the zone abbreviation, and a synthetic zone name
// makes that string unparseable on read. A fabricated zone would fail these
// tests for that reason rather than the one under test.
func inZone(t *testing.T, name string) {
	t.Helper()
	loc, err := time.LoadLocation(name)
	if err != nil {
		t.Skipf("zone %s unavailable: %v", name, err)
	}
	prev := time.Local
	time.Local = loc
	t.Cleanup(func() { time.Local = prev })
}

// The reported bug. A session with hours left on it must validate. Before the
// fix, "hours" was inside the UTC-offset window where the text comparison
// against datetime('now') gave the wrong answer, and this failed.
func TestValidateSession_ValidWithinUTCOffsetWindow(t *testing.T) {
	for _, zone := range []string{
		"America/Los_Angeles", // west of UTC: sessions expired early
		"Pacific/Auckland",    // east of UTC: sessions outlived their expiry
	} {
		t.Run(zone, func(t *testing.T) {
			inZone(t, zone)

			sqlDB, queries := newRenewalTestDB(t)
			token := newSignedInUser(t, queries)

			// One hour of life left — well inside any UTC offset.
			row := readSession(t, sqlDB, token)
			backdate(t, sqlDB, token,
				row.createdAt,
				time.Now().Add(time.Hour),
				row.lastUsedAt,
			)

			if _, _, err := authutil.ValidateSession(context.Background(), queries, token); err != nil {
				t.Fatalf("session with an hour left was rejected: %v", err)
			}
		})
	}
}

// The other direction: the fix must not keep dead sessions alive.
func TestValidateSession_ExpiredWithinUTCOffsetWindow(t *testing.T) {
	for _, zone := range []string{
		"America/Los_Angeles",
		"Pacific/Auckland",
	} {
		t.Run(zone, func(t *testing.T) {
			inZone(t, zone)

			sqlDB, queries := newRenewalTestDB(t)
			token := newSignedInUser(t, queries)

			// Expired an hour ago.
			row := readSession(t, sqlDB, token)
			backdate(t, sqlDB, token,
				row.createdAt,
				time.Now().Add(-time.Hour),
				row.lastUsedAt,
			)

			if _, _, err := authutil.ValidateSession(context.Background(), queries, token); err == nil {
				t.Fatal("session that expired an hour ago was accepted")
			}
		})
	}
}

// What the DSN actually buys: the stored bytes are SQLite's own canonical UTC
// format, so datetime('now') and a stored timestamp are directly comparable.
// Asserting the shape catches a driver upgrade quietly changing it.
func TestSessionTimestampsStoredAsCanonicalUTC(t *testing.T) {
	inZone(t, "America/Los_Angeles")

	sqlDB, queries := newRenewalTestDB(t)
	token := newSignedInUser(t, queries)

	var raw string
	if err := sqlDB.QueryRow(
		`SELECT CAST(expires_at AS TEXT) FROM sessions WHERE token = ?`, digest(token),
	).Scan(&raw); err != nil {
		t.Fatalf("read raw expires_at: %v", err)
	}

	if _, err := time.Parse("2006-01-02 15:04:05", raw); err != nil {
		t.Fatalf("expires_at is not SQLite's canonical format: %q (%v)", raw, err)
	}

	// And it is UTC, not local wall-clock wearing a UTC label: a session
	// created now expires ~30 days out, measured in UTC.
	stored, _ := time.Parse("2006-01-02 15:04:05", raw)
	if delta := stored.Sub(time.Now().UTC()); delta < 29*24*time.Hour || delta > 31*24*time.Hour {
		t.Fatalf("expires_at %q is %s from now in UTC, want ~30 days — looks like local wall-clock", raw, delta)
	}
}

// The DSN is what makes all of the above true, so it must not be possible to
// open a Quark database without it.
func TestDSNCarriesTimeSettings(t *testing.T) {
	for _, path := range []string{":memory:", "/tmp/x.db", "/tmp/x.db?mode=ro"} {
		dsn := db.DSN(path)
		conn, err := sql.Open("sqlite", dsn)
		if err != nil {
			t.Fatalf("open %q: %v", dsn, err)
		}
		// A bad parameter fails the connection rather than being ignored, so a
		// successful round-trip proves the driver accepted both settings.
		if err := conn.Ping(); err != nil {
			t.Fatalf("ping %q: %v", dsn, err)
		}
		conn.Close()
	}
}
