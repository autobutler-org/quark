package main

import (
	"os"
	"path/filepath"
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
