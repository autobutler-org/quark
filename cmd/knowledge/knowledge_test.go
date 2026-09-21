package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newBuilder() *builder {
	return &builder{nodes: map[string]Node{}, edges: map[Edge]struct{}{}}
}

func TestGoLayer(t *testing.T) {
	cases := map[string]string{
		"internal/server/api/v0/albums": "api",
		"internal/server/middleware":    "middleware",
		"internal/server":               "server",
		"internal/db":                   "database",
		"pkg/vfs":                       "vfs",
		"pkg/vfs/local":                 "vfs",
		"pkg/util/fileutil":             "service",
		"cmd/quark":                     "entrypoint",
		"docs/swagger":                  "support",
	}
	for rel, want := range cases {
		if got := goLayer(rel); got != want {
			t.Errorf("goLayer(%q) = %q, want %q", rel, got, want)
		}
	}
}

func TestDartLayer(t *testing.T) {
	cases := map[string]string{
		"lib/pages/files_page.dart":                "page",
		"lib/controllers/files_controller.dart":    "controller",
		"lib/services/files_service.dart":          "service",
		"lib/models/file_item.dart":                "model",
		"lib/widgets/refresh_icon_button.dart":     "app widget",
		"lib/utils/error_text.dart":                "util",
		"lib/main.dart":                            "app",
		"packages/quark_widgets/lib/src/card.dart": "widget package",
	}
	for rel, want := range cases {
		if got := dartLayer(rel); got != want {
			t.Errorf("dartLayer(%q) = %q, want %q", rel, got, want)
		}
	}
}

func TestResolveDartImport(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, filepath.Join(root, "lib", "utils", "helper.dart"), "")
	libDirs := map[string]string{"quark": "lib", "quark_widgets": "packages/quark_widgets/lib"}

	cases := []struct {
		name, from, target, want string
	}{
		{"package import", "lib/pages/files_page.dart", "package:quark/utils/helper.dart", "lib/utils/helper.dart"},
		{"workspace package", "lib/main.dart", "package:quark_widgets/quark_widgets.dart", "packages/quark_widgets/lib/quark_widgets.dart"},
		{"relative import", "lib/pages/files_page.dart", "../utils/helper.dart", "lib/utils/helper.dart"},
		{"sdk import", "lib/main.dart", "dart:io", ""},
		{"external package", "lib/main.dart", "package:http/http.dart", ""},
		{"relative to nothing", "lib/main.dart", "../missing.dart", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := resolveDartImport(root, libDirs, c.from, c.target); got != c.want {
				t.Errorf("resolveDartImport(%q, %q) = %q, want %q", c.from, c.target, got, c.want)
			}
		})
	}
}

func TestHandlerPackage(t *testing.T) {
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "internal", "server", "api", "v0", "albums"), 0o755); err != nil {
		t.Fatal(err)
	}

	want := modulePath + "/internal/server/api/v0/albums"
	if got := handlerPackage(root, "/albums/{id}/items"); got != want {
		t.Errorf("handlerPackage = %q, want %q", got, want)
	}
	// A segment with no handler directory must not invent an edge.
	if got := handlerPackage(root, "/renamed"); got != "" {
		t.Errorf("handlerPackage for unknown segment = %q, want empty", got)
	}
}

func TestCollectDataLinksQueriesToTables(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, filepath.Join(root, "internal", "db", "migrations", "001_init.up.sql"), `
CREATE TABLE users (id INTEGER PRIMARY KEY);
CREATE TABLE IF NOT EXISTS user_sessions (id INTEGER PRIMARY KEY);
`)
	mustWrite(t, filepath.Join(root, "sql", "queries", "users.sql"), `
-- name: GetUser :one
SELECT * FROM users WHERE id = ?;

-- name: ListSessions :many
SELECT * FROM user_sessions;
`)

	b := newBuilder()
	if err := collectData(root, b); err != nil {
		t.Fatal(err)
	}
	g := b.graph()

	for _, id := range []string{"table:users", "table:user_sessions", "query:GetUser", "query:ListSessions"} {
		if _, ok := b.nodes[id]; !ok {
			t.Errorf("missing node %q", id)
		}
	}
	if kind := b.nodes["query:GetUser"].Meta["returns"]; kind != "one" {
		t.Errorf("GetUser returns = %q, want %q", kind, "one")
	}
	if !hasEdge(g, "query:GetUser", "table:users", "touches") {
		t.Error("GetUser should touch users")
	}
	// "users" must not match inside "user_sessions".
	if hasEdge(g, "query:ListSessions", "table:users", "touches") {
		t.Error("ListSessions touches user_sessions, not users")
	}
	if !hasEdge(g, "query:ListSessions", "table:user_sessions", "touches") {
		t.Error("ListSessions should touch user_sessions")
	}
}

func TestCollectJourneys(t *testing.T) {
	root := t.TempDir()
	mustWrite(t, filepath.Join(root, "docs", "user-journeys", "auth.md"), "# Auth\n\n"+
		"### JN-AUTH-001: First-boot setup\n\nApp navigates to `/setup`, then `/files`.\n\n"+
		"### JN-AUTH-002: Log in\n\nLands on `/files`.\n")
	mustWrite(t, filepath.Join(root, "docs", "user-journeys", "README.md"), "### JN-NOPE-001: not a journey\n")

	b := newBuilder()
	// The routes the journeys name have to exist for the edges to survive.
	b.node(Node{ID: "app-route:/setup", Kind: "app-route"})
	b.node(Node{ID: "app-route:/files", Kind: "app-route"})
	if err := collectJourneys(root, b); err != nil {
		t.Fatal(err)
	}
	g := b.graph()

	if _, ok := b.nodes["journey:JN-NOPE-001"]; ok {
		t.Error("README.md should be skipped")
	}
	if doc := b.nodes["journey:JN-AUTH-001"].Doc; doc != "First-boot setup" {
		t.Errorf("journey doc = %q", doc)
	}
	if !hasEdge(g, "journey:JN-AUTH-001", "app-route:/setup", "visits") {
		t.Error("JN-AUTH-001 should visit /setup")
	}
	if !hasEdge(g, "journey:JN-AUTH-001", "app-route:/files", "visits") {
		t.Error("JN-AUTH-001 names /files in its own body")
	}
	// A path named only in the second journey must not leak into the first.
	if !hasEdge(g, "journey:JN-AUTH-002", "app-route:/files", "visits") {
		t.Error("JN-AUTH-002 should visit /files")
	}
	if hasEdge(g, "journey:JN-AUTH-002", "app-route:/setup", "visits") {
		t.Error("JN-AUTH-002 does not name /setup")
	}
}

func TestGraphDropsDanglingEdgesAndSorts(t *testing.T) {
	b := newBuilder()
	b.node(Node{ID: "b"})
	b.node(Node{ID: "a"})
	b.edge("a", "b", "imports")
	b.edge("a", "b", "imports") // duplicate
	b.edge("a", "gone", "imports")
	b.edge("gone", "b", "imports")

	g := b.graph()
	if len(g.Nodes) != 2 || g.Nodes[0].ID != "a" || g.Nodes[1].ID != "b" {
		t.Errorf("nodes = %+v, want sorted [a b]", g.Nodes)
	}
	if len(g.Edges) != 1 {
		t.Fatalf("edges = %+v, want the one edge with both endpoints", g.Edges)
	}
	if g.Edges[0].From != "a" || g.Edges[0].To != "b" {
		t.Errorf("edge = %+v", g.Edges[0])
	}
}

func mustWrite(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
}

func hasEdge(g Graph, from, to, kind string) bool {
	for _, e := range g.Edges {
		if e.From == from && e.To == to && e.Kind == kind {
			return true
		}
	}
	return false
}

func TestDartFileDoc(t *testing.T) {
	cases := []struct {
		name, content, want string
	}{
		{
			name: "class doc at column zero",
			content: "import 'package:flutter/material.dart';\n\n" +
				"/// A sheet that adds one photo to albums.\n///\n/// Longer prose below.\n" +
				"class AddToAlbumSheet extends StatelessWidget {}\n",
			want: "A sheet that adds one photo to albums.",
		},
		{
			name:    "joins the first paragraph",
			content: "/// Percent-encode a path,\n/// keeping the separator.\n\nclass Foo {}\n",
			want:    "Percent-encode a path, keeping the separator.",
		},
		{
			name:    "annotation between doc and declaration",
			content: "/// A generated model.\n@immutable\nclass Model {}\n",
			want:    "A generated model.",
		},
		{
			name:    "barrel documents its library directive",
			content: "/// The spreadsheet data model.\nlibrary;\n\nexport 'src/data_table.dart';\n",
			want:    "The spreadsheet data model.",
		},
		{
			// A doc on an indented member is not the file's summary.
			name:    "indented member doc is ignored",
			content: "class FilesService {\n  /// Construct a thumbnail URL.\n  static Uri build() {}\n}\n",
			want:    "",
		},
		{
			name:    "no doc at all",
			content: "import 'dart:io';\n\nclass Foo {}\n",
			want:    "",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := dartFileDoc(c.content); got != c.want {
				t.Errorf("dartFileDoc = %q, want %q", got, c.want)
			}
		})
	}
}

func TestRouteBuilders(t *testing.T) {
	lines := []string{
		"    GoRoute(",
		"      path: AppRoutes.vault,",
		"      builder: (context, state) => const VaultPage(),",
		"    ),",
		"    GoRoute(path: AppRoutes.jobs, builder: (context, _) => JobsPage()),",
		"    GoRoute(",
		"      path: AppRoutes.setup,",
		"      builder: (context, state) =>",
		"          SetupPage(onSetupComplete: () => context.go(AppRoutes.files)),",
		"    ),",
		"    GoRoute(",
		"      path: AppRoutes.legacyCirrus,",
		"      redirect: (context, state) => AppRoutes.files,",
		"    ),",
	}
	pages := routeBuilders(lines)

	want := map[string]string{"vault": "VaultPage", "jobs": "JobsPage", "setup": "SetupPage"}
	for route, page := range want {
		if pages[route] != page {
			t.Errorf("route %q built by %q, want %q", route, pages[route], page)
		}
	}
	// A redirect-only route has no builder, so it must not borrow a neighbor's.
	if page, ok := pages["legacyCirrus"]; ok {
		t.Errorf("legacyCirrus is redirect-only but got page %q", page)
	}
}

func TestTableColumns(t *testing.T) {
	migration := `CREATE TABLE
    IF NOT EXISTS file_content (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        serial TEXT NOT NULL,
        -- rel_path is relative to the device root.
        rel_path TEXT NOT NULL,
        created_at DATETIME NOT NULL DEFAULT (datetime('now')),
        UNIQUE(serial, rel_path),
        FOREIGN KEY (serial) REFERENCES devices (serial)
    );`

	got := tableColumns(migration, "CREATE TABLE\n    IF NOT EXISTS file_content")
	want := []string{"id", "serial", "rel_path", "created_at"}
	if len(got) != len(want) {
		t.Fatalf("columns = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("column %d = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestQueryDoc(t *testing.T) {
	body := "-- Counts the admins still enabled.\n-- name: CountActiveAdmins :one\nSELECT count(*) FROM users;\n"
	header := len("-- Counts the admins still enabled.\n")
	if got := queryDoc(body, header, "SELECT count(*) FROM users;", []string{"users"}); got != "Counts the admins still enabled." {
		t.Errorf("prose comment = %q", got)
	}

	// With no comment the statement describes itself.
	cases := []struct{ statement, want string }{
		{"SELECT * FROM users;", "Reads users."},
		{"INSERT INTO users (id) VALUES (?);", "Inserts into users."},
		{"UPDATE users SET a = 1;", "Updates users."},
		{"DELETE FROM users;", "Deletes from users."},
		{"WITH t AS (SELECT 1) SELECT * FROM users;", "Reads users."},
		{"PRAGMA foreign_keys;", ""},
	}
	for _, c := range cases {
		if got := queryDoc("-- name: X :one\n", 0, c.statement, []string{"users"}); got != c.want {
			t.Errorf("queryDoc(%q) = %q, want %q", c.statement, got, c.want)
		}
	}
}

func TestTruncate(t *testing.T) {
	if got := truncate("short", 20); got != "short" {
		t.Errorf("truncate left a short string alone: %q", got)
	}
	got := truncate("the quick brown fox jumps over", 15)
	if !strings.HasSuffix(got, "…") || len(got) > 18 {
		t.Errorf("truncate = %q", got)
	}
	if strings.Contains(got, "jumps") {
		t.Errorf("truncate kept too much: %q", got)
	}
}
