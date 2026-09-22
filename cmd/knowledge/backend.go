package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const modulePath = "github.com/autobutler-org/quark"

// goPackage is the subset of `go list -json` this tool reads.
type goPackage struct {
	ImportPath  string
	Dir         string
	Doc         string
	GoFiles     []string
	TestGoFiles []string
	Imports     []string
}

// collectGoPackages maps the backend from `go list`, which resolves build tags and
// the real import graph rather than guessing from import lines.
func collectGoPackages(root string, b *builder) error {
	cmd := exec.Command("go", "list", "-json", "./...")
	cmd.Dir = root
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("go list: %w", err)
	}

	dec := json.NewDecoder(strings.NewReader(string(out)))
	for dec.More() {
		var p goPackage
		if err := dec.Decode(&p); err != nil {
			return fmt.Errorf("go list output: %w", err)
		}
		if !strings.HasPrefix(p.ImportPath, modulePath) {
			continue
		}
		rel := strings.TrimPrefix(strings.TrimPrefix(p.ImportPath, modulePath), "/")
		if rel == "" {
			rel = "."
		}
		b.node(Node{
			ID:    "go:" + p.ImportPath,
			Kind:  "go-package",
			Label: rel,
			Layer: goLayer(rel),
			Path:  rel,
			Doc:   p.Doc,
			Meta: map[string]string{
				"files":      strconv.Itoa(len(p.GoFiles)),
				"test files": strconv.Itoa(len(p.TestGoFiles)),
			},
		})
		for _, imp := range p.Imports {
			if strings.HasPrefix(imp, modulePath) {
				b.edge("go:"+p.ImportPath, "go:"+imp, "imports")
			}
		}
	}
	return nil
}

// goLayer names the architectural layer a package sits in. The names match the ones
// docs/architecture/backend.md uses.
func goLayer(rel string) string {
	switch {
	case strings.HasPrefix(rel, "internal/server/api/"):
		return "api"
	case strings.HasPrefix(rel, "internal/server/middleware"):
		return "middleware"
	case strings.HasPrefix(rel, "internal/server"):
		return "server"
	case strings.HasPrefix(rel, "internal/db"):
		return "database"
	case rel == "pkg/vfs" || strings.HasPrefix(rel, "pkg/vfs/"):
		return "vfs"
	case strings.HasPrefix(rel, "pkg/"):
		return "service"
	case strings.HasPrefix(rel, "cmd/"):
		return "entrypoint"
	default:
		return "support"
	}
}

// swaggerSpec is the subset of the generated OpenAPI document this tool reads.
type swaggerSpec struct {
	Paths map[string]map[string]struct {
		Summary string   `json:"summary"`
		Tags    []string `json:"tags"`
	} `json:"paths"`
}

// collectRoutes reads the generated swagger spec, so the route list is whatever the
// handler annotations actually say rather than a second inventory that can drift.
func collectRoutes(root string, b *builder) error {
	raw, err := os.ReadFile(filepath.Join(root, "docs", "swagger", "swagger.json"))
	if err != nil {
		return fmt.Errorf("swagger spec: %w", err)
	}
	var spec swaggerSpec
	if err := json.Unmarshal(raw, &spec); err != nil {
		return fmt.Errorf("swagger spec: %w", err)
	}

	for path, ops := range spec.Paths {
		for method, op := range ops {
			up := strings.ToUpper(method)
			id := "route:" + up + " " + path
			meta := map[string]string{"method": up}
			if len(op.Tags) > 0 {
				meta["tag"] = strings.Join(op.Tags, ", ")
			}
			b.node(Node{
				ID:    id,
				Kind:  "route",
				Label: up + " /api/v0" + path,
				Layer: "api",
				Doc:   op.Summary,
				Meta:  meta,
			})
			if pkg := handlerPackage(root, path); pkg != "" {
				b.edge("go:"+pkg, id, "handles")
			}
		}
	}
	return nil
}

// handlerPackage maps a route's first path segment to the handler directory that
// serves it, which is the naming rule AGENTS.md enforces. It returns "" when no such
// directory exists, so a renamed segment drops the edge instead of inventing one.
func handlerPackage(root, path string) string {
	segments := strings.Split(strings.TrimPrefix(path, "/"), "/")
	if len(segments) == 0 || segments[0] == "" {
		return ""
	}
	rel := filepath.Join("internal", "server", "api", "v0", segments[0])
	if info, err := os.Stat(filepath.Join(root, rel)); err != nil || !info.IsDir() {
		return ""
	}
	return modulePath + "/" + filepath.ToSlash(rel)
}

var (
	createTableRe = regexp.MustCompile(`(?is)CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[` + "`" + `"\[]?([a-zA-Z_][a-zA-Z0-9_]*)`)
	queryNameRe   = regexp.MustCompile(`(?m)^--\s*name:\s*(\w+)\s*(:\w+)?`)

	// A leading CTE is common enough that the verb check has to look past it.
	cte      = `(?is)^\s*(?:WITH\b.*?\)\s*)?`
	selectRe = regexp.MustCompile(cte + `SELECT\b`)
	insertRe = regexp.MustCompile(cte + `INSERT\b`)
	updateRe = regexp.MustCompile(cte + `UPDATE\b`)
	deleteRe = regexp.MustCompile(cte + `DELETE\b`)
)

// collectData reads the migrations for the schema and sql/queries for the sqlc
// queries, then links each query to the tables its text names.
func collectData(root string, b *builder) error {
	migrations, err := filepath.Glob(filepath.Join(root, "internal", "db", "migrations", "*.up.sql"))
	if err != nil {
		return err
	}
	sort.Strings(migrations)

	// Table name -> a matcher for it, on word boundaries so "users" does not match
	// "users_sessions".
	tables := map[string]*regexp.Regexp{}
	for _, m := range migrations {
		raw, err := os.ReadFile(m)
		if err != nil {
			return err
		}
		for _, match := range createTableRe.FindAllStringSubmatch(string(raw), -1) {
			name := match[1]
			if _, seen := tables[name]; seen {
				continue
			}
			tables[name] = regexp.MustCompile(`(?i)\b` + regexp.QuoteMeta(name) + `\b`)
			meta := map[string]string{"created by": filepath.Base(m)}
			doc := ""
			if columns := tableColumns(string(raw), match[0]); len(columns) > 0 {
				meta["columns"] = strconv.Itoa(len(columns))
				doc = "Columns: " + truncate(strings.Join(columns, ", "), 200)
			}
			b.node(Node{
				Kind:  "table",
				ID:    "table:" + name,
				Label: name,
				Layer: "database",
				Path:  filepath.ToSlash(filepath.Join("internal", "db", "migrations", filepath.Base(m))),
				Doc:   doc,
				Meta:  meta,
			})
		}
	}

	queries, err := filepath.Glob(filepath.Join(root, "sql", "queries", "*.sql"))
	if err != nil {
		return err
	}
	sort.Strings(queries)

	for _, q := range queries {
		raw, err := os.ReadFile(q)
		if err != nil {
			return err
		}
		rel := filepath.ToSlash(filepath.Join("sql", "queries", filepath.Base(q)))
		body := string(raw)
		locations := queryNameRe.FindAllStringSubmatchIndex(body, -1)
		for i, loc := range locations {
			name := body[loc[2]:loc[3]]
			kind := ""
			if loc[4] >= 0 {
				kind = strings.TrimPrefix(body[loc[4]:loc[5]], ":")
			}
			end := len(body)
			if i+1 < len(locations) {
				end = locations[i+1][0]
			}
			statement := body[loc[1]:end]

			id := "query:" + name
			meta := map[string]string{"file": filepath.Base(q)}
			if kind != "" {
				meta["returns"] = kind
			}

			var touched []string
			for table, matcher := range tables {
				if matcher.MatchString(statement) {
					b.edge(id, "table:"+table, "touches")
					touched = append(touched, table)
				}
			}
			sort.Strings(touched)

			b.node(Node{
				ID:    id,
				Kind:  "query",
				Label: name,
				Layer: "database",
				Path:  rel,
				Doc:   queryDoc(body, loc[0], statement, touched),
				Meta:  meta,
			})
		}
	}
	return nil
}

// tableColumns pulls the column names out of a CREATE TABLE body, skipping the
// table-level constraints that share the same comma-separated list.
func tableColumns(migration, createClause string) []string {
	start := strings.Index(migration, createClause)
	if start < 0 {
		return nil
	}
	open := strings.Index(migration[start:], "(")
	if open < 0 {
		return nil
	}
	open += start

	depth, end := 0, -1
	for i := open; i < len(migration) && end < 0; i++ {
		switch migration[i] {
		case '(':
			depth++
		case ')':
			depth--
			if depth == 0 {
				end = i
			}
		}
	}
	if end < 0 {
		return nil
	}

	var columns []string
	depth = 0
	var field strings.Builder
	flush := func() {
		entry := strings.TrimSpace(field.String())
		field.Reset()
		// A table-level constraint can open its parenthesis with no space —
		// UNIQUE(serial, rel_path) — so the name ends at punctuation, not just space.
		name := entry
		if cut := strings.IndexAny(entry, " \t("); cut >= 0 {
			name = entry[:cut]
		}
		name = strings.Trim(name, "`\"[]")
		if name == "" || isConstraintKeyword(name) {
			return
		}
		columns = append(columns, name)
	}
	for _, r := range stripSQLComments(migration[open+1 : end]) {
		switch {
		case r == '(':
			depth++
		case r == ')':
			depth--
		case r == ',' && depth == 0:
			flush()
			continue
		case r == '\n' || r == '\t':
			r = ' '
		}
		field.WriteRune(r)
	}
	flush()
	return columns
}

// stripSQLComments drops `--` to end of line. Migrations annotate columns inline, and
// the comment text would otherwise be read as further columns.
func stripSQLComments(s string) string {
	lines := strings.Split(s, "\n")
	for i, line := range lines {
		if idx := strings.Index(line, "--"); idx >= 0 {
			lines[i] = line[:idx]
		}
	}
	return strings.Join(lines, "\n")
}

// isConstraintKeyword reports whether a comma-separated entry in a CREATE TABLE body
// is a table-level constraint rather than a column.
func isConstraintKeyword(word string) bool {
	switch strings.ToUpper(word) {
	case "PRIMARY", "FOREIGN", "UNIQUE", "CHECK", "CONSTRAINT":
		return true
	}
	return false
}

// queryDoc prefers the comment a query was written with, and otherwise says what the
// statement does in one mechanical sentence.
func queryDoc(body string, headerStart int, statement string, touched []string) string {
	if prose := commentAbove(body, headerStart); prose != "" {
		return prose
	}
	verb := ""
	switch {
	case selectRe.MatchString(statement):
		verb = "Reads"
	case insertRe.MatchString(statement):
		verb = "Inserts into"
	case updateRe.MatchString(statement):
		verb = "Updates"
	case deleteRe.MatchString(statement):
		verb = "Deletes from"
	default:
		return ""
	}
	if len(touched) == 0 {
		return verb + " the database."
	}
	return verb + " " + strings.Join(touched, ", ") + "."
}

// commentAbove reads the `--` lines directly above a query's name header, stopping at
// a blank line or another header.
func commentAbove(body string, headerStart int) string {
	// Drop only the newline that ends the line above the header. Trimming more would
	// let a comment separated by a blank line attach to a query it does not describe.
	lines := strings.Split(strings.TrimSuffix(body[:headerStart], "\n"), "\n")
	var block []string
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			break
		}
		if !strings.HasPrefix(line, "--") || queryNameRe.MatchString(line) {
			break
		}
		block = append([]string{strings.TrimSpace(strings.TrimPrefix(line, "--"))}, block...)
	}
	if len(block) == 0 {
		return ""
	}
	return truncate(strings.Join(block, " "), 240)
}
