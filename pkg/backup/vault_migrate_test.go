package backup

import (
	"context"
	"database/sql"
	"fmt"
	"sync/atomic"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	_ "modernc.org/sqlite"
)

var testDBCounter uint64

func openTestVaultDB(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	n := atomic.AddUint64(&testDBCounter, 1)
	dsn := fmt.Sprintf("file:testdb%d?mode=memory&cache=shared", n)
	d, err := sql.Open("sqlite", dsn)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.InitVaultSchema(d); err != nil {
		t.Fatal(err)
	}
	conn, err := d.Conn(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return &db.DatabaseSqlc{Db: d, Queries: db.New(conn)}
}

func seedVault(t *testing.T, d *db.DatabaseSqlc) {
	t.Helper()
	ctx := context.Background()
	_, err := d.Db.ExecContext(ctx,
		`INSERT INTO vault_config (id, salt, argon2_memory, argon2_iterations, argon2_parallelism,
			verification_blob, verification_nonce, auto_lock_seconds)
		VALUES (1, x'aabb', 65536, 3, 4, x'ccdd', x'eeff', 900)`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = d.Db.ExecContext(ctx,
		`INSERT INTO vault_folders (id, name, sort_order) VALUES (1, 'Social', 0), (2, 'Work', 1)`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = d.Db.ExecContext(ctx,
		`INSERT INTO vault_entries (id, name, url_host, folder_id, ciphertext, nonce)
		VALUES (1, 'GitHub', 'github.com', 1, x'1111', x'2222'),
		       (2, 'Slack', 'slack.com', 2, x'3333', x'4444')`)
	if err != nil {
		t.Fatal(err)
	}
}

func countRows(t *testing.T, d *sql.DB, table string) int {
	t.Helper()
	var n int
	if err := d.QueryRow("SELECT count(*) FROM " + table).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func TestMigrateVault(t *testing.T) {
	src := openTestVaultDB(t)
	defer src.Db.Close()
	dst := openTestVaultDB(t)
	defer dst.Db.Close()

	seedVault(t, src)

	if err := MigrateVault(context.Background(), src, dst); err != nil {
		t.Fatalf("MigrateVault: %v", err)
	}

	if n := countRows(t, dst.Db, "vault_config"); n != 1 {
		t.Errorf("vault_config rows = %d, want 1", n)
	}
	if n := countRows(t, dst.Db, "vault_folders"); n != 2 {
		t.Errorf("vault_folders rows = %d, want 2", n)
	}
	if n := countRows(t, dst.Db, "vault_entries"); n != 2 {
		t.Errorf("vault_entries rows = %d, want 2", n)
	}

	var name string
	if err := dst.Db.QueryRow("SELECT name FROM vault_entries WHERE id = 1").Scan(&name); err != nil {
		t.Fatal(err)
	}
	if name != "GitHub" {
		t.Errorf("entry name = %q, want GitHub", name)
	}
}

func TestMigrateVault_EmptySource(t *testing.T) {
	src := openTestVaultDB(t)
	defer src.Db.Close()
	dst := openTestVaultDB(t)
	defer dst.Db.Close()

	if err := MigrateVault(context.Background(), src, dst); err != nil {
		t.Fatalf("MigrateVault empty: %v", err)
	}

	if n := countRows(t, dst.Db, "vault_config"); n != 0 {
		t.Errorf("vault_config rows = %d, want 0", n)
	}
}

func TestTruncateVaultTables(t *testing.T) {
	d := openTestVaultDB(t)
	defer d.Db.Close()
	seedVault(t, d)

	if err := TruncateVaultTables(context.Background(), d); err != nil {
		t.Fatalf("TruncateVaultTables: %v", err)
	}

	for _, table := range []string{"vault_entries", "vault_folders", "vault_config"} {
		if n := countRows(t, d.Db, table); n != 0 {
			t.Errorf("%s rows = %d, want 0", table, n)
		}
	}
}

func TestMigrateVault_PreservesTimestamps(t *testing.T) {
	src := openTestVaultDB(t)
	defer src.Db.Close()
	dst := openTestVaultDB(t)
	defer dst.Db.Close()

	ctx := context.Background()
	_, err := src.Db.ExecContext(ctx,
		`INSERT INTO vault_config (id, salt, argon2_memory, argon2_iterations, argon2_parallelism,
			verification_blob, verification_nonce, auto_lock_seconds, created_at)
		VALUES (1, x'aa', 65536, 3, 4, x'bb', x'cc', 900, '2024-01-15 10:30:00')`)
	if err != nil {
		t.Fatal(err)
	}

	if err := MigrateVault(ctx, src, dst); err != nil {
		t.Fatal(err)
	}

	var createdAt string
	if err := dst.Db.QueryRow("SELECT created_at FROM vault_config WHERE id = 1").Scan(&createdAt); err != nil {
		t.Fatal(err)
	}
	if createdAt != "2024-01-15 10:30:00" && createdAt != "2024-01-15T10:30:00Z" {
		t.Errorf("created_at = %q, want 2024-01-15 10:30:00", createdAt)
	}
}

func TestMigrateVault_FolderParentIDs(t *testing.T) {
	src := openTestVaultDB(t)
	defer src.Db.Close()
	dst := openTestVaultDB(t)
	defer dst.Db.Close()

	ctx := context.Background()
	_, err := src.Db.ExecContext(ctx,
		`INSERT INTO vault_config (id, salt, argon2_memory, argon2_iterations, argon2_parallelism,
			verification_blob, verification_nonce, auto_lock_seconds)
		VALUES (1, x'aa', 65536, 3, 4, x'bb', x'cc', 900)`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = src.Db.ExecContext(ctx,
		`INSERT INTO vault_folders (id, name, sort_order) VALUES (1, 'Parent', 0)`)
	if err != nil {
		t.Fatal(err)
	}
	_, err = src.Db.ExecContext(ctx,
		`INSERT INTO vault_folders (id, name, parent_id, sort_order) VALUES (2, 'Child', 1, 1)`)
	if err != nil {
		t.Fatal(err)
	}

	if err := MigrateVault(ctx, src, dst); err != nil {
		t.Fatal(err)
	}

	var parentID sql.NullInt64
	if err := dst.Db.QueryRow("SELECT parent_id FROM vault_folders WHERE id = 2").Scan(&parentID); err != nil {
		t.Fatal(err)
	}
	if !parentID.Valid || parentID.Int64 != 1 {
		t.Errorf("child parent_id = %v, want 1", parentID)
	}
}

// A move cut short after its copy committed leaves a vault in the target. The
// retry replaces it rather than failing on its ids (#2517).
func TestMigrateVault_ReplacesAnEarlierCopy(t *testing.T) {
	ctx := context.Background()
	src := openTestVaultDB(t)
	defer src.Db.Close()
	dst := openTestVaultDB(t)
	defer dst.Db.Close()

	seedVault(t, src)
	if err := MigrateVault(ctx, src, dst); err != nil {
		t.Fatalf("first MigrateVault: %v", err)
	}
	if _, err := src.Db.ExecContext(ctx, `DELETE FROM vault_entries WHERE id = 2`); err != nil {
		t.Fatal(err)
	}
	if err := MigrateVault(ctx, src, dst); err != nil {
		t.Fatalf("retried MigrateVault: %v", err)
	}

	if n := countRows(t, dst.Db, "vault_config"); n != 1 {
		t.Errorf("vault_config rows = %d, want 1", n)
	}
	if n := countRows(t, dst.Db, "vault_entries"); n != 1 {
		t.Errorf("vault_entries rows = %d, want the source's 1", n)
	}
}
