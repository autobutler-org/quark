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
			b.node(Node{
				Kind:  "table",
				ID:    "table:" + name,
				Label: name,
				Layer: "database",
				Path:  filepath.ToSlash(filepath.Join("internal", "db", "migrations", filepath.Base(m))),
				Meta:  map[string]string{"created by": filepath.Base(m)},
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
			b.node(Node{
				ID:    id,
				Kind:  "query",
				Label: name,
				Layer: "database",
				Path:  rel,
				Meta:  meta,
			})
			for table, matcher := range tables {
				if matcher.MatchString(statement) {
					b.edge(id, "table:"+table, "touches")
				}
			}
		}
	}
	return nil
}
