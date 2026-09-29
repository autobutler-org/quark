package vaultutil

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	_ "modernc.org/sqlite"
)

// testKey stands in for a derived vault key. Deriving a real one costs an
// Argon2 pass per test and proves nothing these tests are checking.
var testKey = bytes.Repeat([]byte{7}, 32)

func openTestVault(t *testing.T) *db.DatabaseSqlc {
	t.Helper()
	d, err := sql.Open("sqlite", filepath.Join(t.TempDir(), "vault.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { d.Close() })
	if err := db.InitVaultSchema(d); err != nil {
		t.Fatal(err)
	}
	return &db.DatabaseSqlc{Db: d, Queries: db.New(d)}
}

const bitwardenExport = `folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
Social,,login,GitHub,gh notes,,0,https://github.com/login,alice,gh-pass,JBSWY3DPEHPK3PXP
Banking,,login,Chase,,,,https://chase.com,bob,chase-pw,
`

func TestImport_CreatesEntriesAndFolders(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)

	result, err := Import(ctx, ImportParams{
		VaultDB: vault,
		Key:     testKey,
		Data:    []byte(bitwardenExport),
		Format:  FormatAuto,
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.Imported != 2 || result.Skipped != 0 {
		t.Fatalf("imported=%d skipped=%d, want 2/0 (errors: %v)", result.Imported, result.Skipped, result.Errors)
	}

	folders, err := ListFolders(ctx, ListFoldersParams{Queries: vault.Queries})
	if err != nil {
		t.Fatal(err)
	}
	if len(folders.Folders) != 2 {
		t.Fatalf("expected the import to create 2 folders, got %d", len(folders.Folders))
	}

	entries, err := ListEntries(ctx, ListEntriesParams{Queries: vault.Queries})
	if err != nil {
		t.Fatal(err)
	}
	if len(entries.Entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries.Entries))
	}
	github := findEntry(t, entries.Entries, "GitHub")
	if github.URLHost != "github.com" {
		t.Errorf("urlHost = %q, want github.com", github.URLHost)
	}

	// The secret half must come back out from under the key.
	got, err := GetEntry(ctx, GetEntryParams{Queries: vault.Queries, Key: testKey, ID: github.ID})
	if err != nil {
		t.Fatal(err)
	}
	if got.Entry.Password != "gh-pass" || got.Entry.TOTPSecret != "JBSWY3DPEHPK3PXP" {
		t.Errorf("decrypted entry = %+v", got.Entry)
	}
}

func TestImport_SkipsDuplicatesOnReimport(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)
	params := ImportParams{VaultDB: vault, Key: testKey, Data: []byte(bitwardenExport), Format: FormatAuto}

	if _, err := Import(ctx, params); err != nil {
		t.Fatal(err)
	}

	second, err := Import(ctx, params)
	if err != nil {
		t.Fatal(err)
	}
	if second.Imported != 0 || second.Skipped != 2 {
		t.Fatalf("imported=%d skipped=%d, want 0/2", second.Imported, second.Skipped)
	}
}

func TestImport_UnsupportedFormat(t *testing.T) {
	_, err := Import(context.Background(), ImportParams{
		VaultDB: openTestVault(t),
		Key:     testKey,
		Data:    []byte("whatever"),
		Format:  "keepass-xml",
	})
	if !errors.Is(err, ErrUnsupportedImportFormat) {
		t.Fatalf("err = %v, want ErrUnsupportedImportFormat", err)
	}
}

func TestEntryLifecycle(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)

	created, err := CreateEntry(ctx, CreateEntryParams{
		Queries: vault.Queries,
		Key:     testKey,
		Fields: EntryFields{
			Name:         "GitHub",
			URL:          "https://github.com/login",
			Username:     "alice",
			Password:     "gh-pass",
			CustomFields: []CustomField{{Name: "PIN", Value: "1234", Hidden: true}},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	if created.Entry.URLHost != "github.com" {
		t.Errorf("urlHost = %q, want github.com", created.Entry.URLHost)
	}

	if _, err := UpdateEntry(ctx, UpdateEntryParams{
		Queries: vault.Queries,
		Key:     testKey,
		ID:      created.Entry.ID,
		Fields:  EntryFields{Name: "GitHub", URL: "https://github.com", Username: "alice", Password: "rotated"},
	}); err != nil {
		t.Fatal(err)
	}

	got, err := GetEntry(ctx, GetEntryParams{Queries: vault.Queries, Key: testKey, ID: created.Entry.ID})
	if err != nil {
		t.Fatal(err)
	}
	if got.Entry.Password != "rotated" {
		t.Errorf("password = %q, want rotated", got.Entry.Password)
	}
	if got.Entry.CustomFields != nil {
		t.Errorf("update replaces the payload wholesale, so custom fields should be gone: %+v", got.Entry.CustomFields)
	}

	if _, err := DeleteEntry(ctx, DeleteEntryParams{Queries: vault.Queries, ID: created.Entry.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := GetEntry(ctx, GetEntryParams{Queries: vault.Queries, Key: testKey, ID: created.Entry.ID}); !errors.Is(err, ErrEntryNotFound) {
		t.Fatalf("err = %v, want ErrEntryNotFound", err)
	}
}

func TestUpdateEntry_MissingID(t *testing.T) {
	vault := openTestVault(t)
	_, err := UpdateEntry(context.Background(), UpdateEntryParams{
		Queries: vault.Queries,
		Key:     testKey,
		ID:      404,
		Fields:  EntryFields{Name: "nope"},
	})
	if !errors.Is(err, ErrEntryNotFound) {
		t.Fatalf("err = %v, want ErrEntryNotFound", err)
	}
}

func TestFolderLifecycle(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)

	created, err := CreateFolder(ctx, CreateFolderParams{
		Queries: vault.Queries,
		Fields:  FolderFields{Name: "Social", SortOrder: 3},
	})
	if err != nil {
		t.Fatal(err)
	}

	if _, err := UpdateFolder(ctx, UpdateFolderParams{
		Queries: vault.Queries,
		ID:      created.Folder.ID,
		Fields:  FolderFields{Name: "Renamed", SortOrder: 1},
	}); err != nil {
		t.Fatal(err)
	}

	folders, err := ListFolders(ctx, ListFoldersParams{Queries: vault.Queries})
	if err != nil {
		t.Fatal(err)
	}
	if len(folders.Folders) != 1 || folders.Folders[0].Name != "Renamed" {
		t.Fatalf("folders = %+v", folders.Folders)
	}

	if _, err := DeleteFolder(ctx, DeleteFolderParams{Queries: vault.Queries, ID: created.Folder.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := UpdateFolder(ctx, UpdateFolderParams{
		Queries: vault.Queries,
		ID:      created.Folder.ID,
		Fields:  FolderFields{Name: "gone"},
	}); !errors.Is(err, ErrFolderNotFound) {
		t.Fatalf("err = %v, want ErrFolderNotFound", err)
	}
}

// An export must feed straight back into an import, since that is the pair a
// user reaches for when moving between machines.
func TestExport_RoundTripsThroughImport(t *testing.T) {
	ctx := context.Background()
	source := openTestVault(t)

	if _, err := Import(ctx, ImportParams{
		VaultDB: source,
		Key:     testKey,
		Data:    []byte(bitwardenExport),
		Format:  FormatAuto,
	}); err != nil {
		t.Fatal(err)
	}

	exported, err := Export(ctx, ExportParams{Queries: source.Queries, Key: testKey})
	if err != nil {
		t.Fatal(err)
	}
	if len(exported.Entries) != 2 || len(exported.FolderNames) != 2 {
		t.Fatalf("entries=%d folders=%d, want 2/2", len(exported.Entries), len(exported.FolderNames))
	}
	for _, e := range exported.Entries {
		if e.Name == "GitHub" && e.FolderName != "Social" {
			t.Errorf("GitHub folderName = %q, want Social", e.FolderName)
		}
	}

	reimported, errs := ParseQuarkJSON(mustMarshalJSON(t, ExportJSON{
		Entries: exported.Entries,
		Folders: exported.FolderNames,
	}))
	if len(errs) > 0 {
		t.Fatalf("unexpected parse errors: %v", errs)
	}
	if len(reimported) != 2 || reimported[0].Password == "" {
		t.Fatalf("reimported = %+v", reimported)
	}
}

func mustMarshalJSON(t *testing.T, v any) []byte {
	t.Helper()
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return data
}

func findEntry(t *testing.T, entries []EntryListItem, name string) EntryListItem {
	t.Helper()
	for _, e := range entries {
		if e.Name == name {
			return e
		}
	}
	t.Fatalf("no entry named %q in %+v", name, entries)
	return EntryListItem{}
}

func TestImport_ProtonPassReportsIgnoredItems(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)

	result, err := Import(ctx, ImportParams{VaultDB: vault, Key: testKey, Data: []byte(protonPassExport), Format: FormatAuto})
	if err != nil {
		t.Fatal(err)
	}
	if result.Imported != 2 || result.Ignored != 3 || len(result.Errors) != 1 {
		t.Fatalf("result = %+v, want 2 imported, 3 ignored, 1 error", result)
	}

	list, err := ListEntries(ctx, ListEntriesParams{Queries: vault.Queries})
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range list.Entries {
		if entry.Name != "GitHub" {
			continue
		}
		detail, err := GetEntry(ctx, GetEntryParams{Queries: vault.Queries, Key: testKey, ID: entry.ID})
		if err != nil {
			t.Fatal(err)
		}
		if detail.Entry.TOTPSecret != "JBSWY3DPEHPK3PXP" || detail.Entry.URLHost != "github.com" {
			t.Errorf("imported GitHub entry = %+v", detail.Entry)
		}
		return
	}
	t.Fatal("GitHub entry not imported")
}

func TestImportResult_OmitsIgnoredWhenZero(t *testing.T) {
	encoded, err := json.Marshal(ImportResult{Imported: 1})
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "ignored") {
		t.Errorf("result %s carries ignored; existing clients should see no change", encoded)
	}
}

func TestBackfillEntryHosts_FillsHostsSavedWithoutAScheme(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)

	legacy := func(name, rawURL string) int64 {
		t.Helper()
		ciphertext, nonce, err := encryptFields(testKey, EntryFields{Name: name, URL: rawURL, Password: "pw"})
		if err != nil {
			t.Fatal(err)
		}
		row, err := vault.Queries.CreateVaultEntry(ctx, db.CreateVaultEntryParams{
			Name:       name,
			UrlHost:    "",
			Ciphertext: ciphertext,
			Nonce:      nonce,
		})
		if err != nil {
			t.Fatal(err)
		}
		return row.ID
	}
	github := legacy("GitHub", "github.com/login")
	noURL := legacy("Wi-Fi", "")

	result, err := BackfillEntryHosts(ctx, BackfillEntryHostsParams{Queries: vault.Queries, Key: testKey})
	if err != nil {
		t.Fatal(err)
	}
	if result.Updated != 1 {
		t.Fatalf("updated = %d, want 1", result.Updated)
	}

	hosts := map[int64]string{}
	list, err := ListEntries(ctx, ListEntriesParams{Queries: vault.Queries})
	if err != nil {
		t.Fatal(err)
	}
	for _, entry := range list.Entries {
		hosts[entry.ID] = entry.URLHost
	}
	if hosts[github] != "github.com" {
		t.Errorf("github host = %q, want github.com", hosts[github])
	}
	if hosts[noURL] != "" {
		t.Errorf("entry without a URL got host %q", hosts[noURL])
	}

	again, err := BackfillEntryHosts(ctx, BackfillEntryHostsParams{Queries: vault.Queries, Key: testKey})
	if err != nil {
		t.Fatal(err)
	}
	if again.Updated != 0 {
		t.Errorf("second run updated %d entries, want 0", again.Updated)
	}
}

func TestBackfillEntryHosts_SkipsEntriesItCannotDecrypt(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)

	ciphertext, nonce, err := encryptFields(bytes.Repeat([]byte{9}, 32), EntryFields{Name: "Other key", URL: "example.com"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := vault.Queries.CreateVaultEntry(ctx, db.CreateVaultEntryParams{Name: "Other key", Ciphertext: ciphertext, Nonce: nonce}); err != nil {
		t.Fatal(err)
	}

	result, err := BackfillEntryHosts(ctx, BackfillEntryHostsParams{Queries: vault.Queries, Key: testKey})
	if err != nil {
		t.Fatal(err)
	}
	if result.Updated != 0 {
		t.Fatalf("updated = %d, want 0", result.Updated)
	}
}

func TestCreateEntry_StoresHostForURLWithoutScheme(t *testing.T) {
	ctx := context.Background()
	vault := openTestVault(t)

	created, err := CreateEntry(ctx, CreateEntryParams{
		Queries: vault.Queries,
		Key:     testKey,
		Fields:  EntryFields{Name: "GitHub", URL: "GitHub.com/login", Password: "pw"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if created.Entry.URLHost != "github.com" {
		t.Fatalf("urlHost = %q, want github.com", created.Entry.URLHost)
	}
}
