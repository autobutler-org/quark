package main

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var (
	dartImportRe = regexp.MustCompile(`(?m)^\s*(?:import|export)\s+'([^']+)'`)
	appRouteRe   = regexp.MustCompile(`(?m)^\s*static\s+const\s+(\w+)\s*=\s*'(/[^']*)'`)
	pubNameRe    = regexp.MustCompile(`(?m)^name:\s*(\S+)`)
)

// collectDart maps the Flutter side: every Dart file under lib/ and each workspace
// package's lib/, plus the import edges between them.
func collectDart(root string, b *builder) error {
	libDirs, err := dartLibDirs(root)
	if err != nil {
		return err
	}

	for pkgName, libDir := range libDirs {
		err := filepath.WalkDir(filepath.Join(root, libDir), func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() || !strings.HasSuffix(path, ".dart") {
				return nil
			}
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}
			rel = filepath.ToSlash(rel)
			raw, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			b.node(Node{
				ID:    "dart:" + rel,
				Kind:  "dart-file",
				Label: rel,
				Layer: dartLayer(rel),
				Path:  rel,
				Doc:   dartFileDoc(string(raw)),
				Meta:  map[string]string{"package": pkgName},
			})

			for _, m := range dartImportRe.FindAllStringSubmatch(string(raw), -1) {
				if target := resolveDartImport(root, libDirs, rel, m[1]); target != "" {
					b.edge("dart:"+rel, "dart:"+target, "imports")
				}
			}
			return nil
		})
		if err != nil {
			return fmt.Errorf("walking %s: %w", libDir, err)
		}
	}

	return collectAppRoutes(root, b)
}

// dartLibDirs maps each workspace package's pub name to its lib/ directory, read from
// the pubspec so a renamed or added package is picked up without editing this tool.
func dartLibDirs(root string) (map[string]string, error) {
	dirs := map[string]string{}
	pubspecs, err := filepath.Glob(filepath.Join(root, "packages", "*", "pubspec.yaml"))
	if err != nil {
		return nil, err
	}
	pubspecs = append(pubspecs, filepath.Join(root, "pubspec.yaml"))

	for _, p := range pubspecs {
		raw, err := os.ReadFile(p)
		if err != nil {
			return nil, err
		}
		m := pubNameRe.FindStringSubmatch(string(raw))
		if m == nil {
			continue
		}
		libDir, err := filepath.Rel(root, filepath.Join(filepath.Dir(p), "lib"))
		if err != nil {
			return nil, err
		}
		if _, err := os.Stat(filepath.Join(root, libDir)); err != nil {
			continue
		}
		dirs[m[1]] = filepath.ToSlash(libDir)
	}
	return dirs, nil
}

// resolveDartImport turns an import string into a repository-relative path, or ""
// for anything outside the workspace (dart:, package:flutter, pub dependencies).
func resolveDartImport(root string, libDirs map[string]string, from, target string) string {
	if strings.HasPrefix(target, "dart:") {
		return ""
	}
	if strings.HasPrefix(target, "package:") {
		rest := strings.TrimPrefix(target, "package:")
		name, path, found := strings.Cut(rest, "/")
		if !found {
			return ""
		}
		libDir, ok := libDirs[name]
		if !ok {
			return ""
		}
		return libDir + "/" + path
	}
	resolved := filepath.ToSlash(filepath.Join(filepath.Dir(from), target))
	if _, err := os.Stat(filepath.Join(root, resolved)); err != nil {
		return ""
	}
	return resolved
}

// dartFileDoc returns the first `///` block that documents a top-level declaration,
// which in this codebase is the file's main class, or the `library;` directive a
// barrel or multi-declaration file documents instead. Both the comment and the thing it
// documents have to sit at column zero, so a doc on an indented member — a route
// constant inside AppRoutes, say — is not mistaken for the file's own summary.
//
// It returns "" when nothing qualifies, because a wrong description is worse than none.
func dartFileDoc(content string) string {
	lines := strings.Split(content, "\n")
	for i := 0; i < len(lines); i++ {
		if !strings.HasPrefix(lines[i], "///") {
			continue
		}
		end := i
		for end < len(lines) && strings.HasPrefix(lines[end], "///") {
			end++
		}
		// Annotations sit between the doc and the declaration.
		next := end
		for next < len(lines) && (strings.TrimSpace(lines[next]) == "" || strings.HasPrefix(lines[next], "@")) {
			next++
		}
		if next < len(lines) && declaresTopLevel(lines[next]) {
			return firstParagraph(lines[i:end])
		}
		i = end
	}
	return ""
}

// declaresTopLevel reports whether a column-zero line begins a declaration, or the
// library directive, rather than another directive or a comment.
func declaresTopLevel(line string) bool {
	if line == "" || line != strings.TrimLeft(line, " \t") {
		return false
	}
	for _, skip := range []string{"//", "/*", "*", "import ", "export ", "part ", "@"} {
		if strings.HasPrefix(line, skip) {
			return false
		}
	}
	return true
}

// firstParagraph joins a `///` run up to its first blank line into one sentence of
// prose, so a long class doc contributes its summary rather than its whole body.
func firstParagraph(block []string) string {
	var parts []string
	for _, l := range block {
		text := strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(l, "///"), " "))
		if text == "" {
			break
		}
		parts = append(parts, text)
	}
	return truncate(strings.Join(parts, " "), 240)
}

// truncate keeps a description to one readable line, cutting at a word boundary.
func truncate(s string, limit int) string {
	if len(s) <= limit {
		return s
	}
	cut := strings.LastIndex(s[:limit], " ")
	if cut < limit/2 {
		cut = limit
	}
	return strings.TrimRight(s[:cut], " ,;:") + "…"
}

// dartLayer names the layer a Dart file sits in, following the structure AGENTS.md
// lays out for lib/.
func dartLayer(rel string) string {
	switch {
	case strings.HasPrefix(rel, "packages/"):
		return "widget package"
	case strings.HasPrefix(rel, "lib/pages/"):
		return "page"
	case strings.HasPrefix(rel, "lib/controllers/"):
		return "controller"
	case strings.HasPrefix(rel, "lib/services/"):
		return "service"
	case strings.HasPrefix(rel, "lib/models/"):
		return "model"
	case strings.HasPrefix(rel, "lib/widgets/"):
		return "app widget"
	case strings.HasPrefix(rel, "lib/utils/"):
		return "util"
	default:
		return "app"
	}
}

// collectAppRoutes reads the AppRoutes constants, the single place lib/router.dart
// declares a client route path.
func collectAppRoutes(root string, b *builder) error {
	rel := filepath.ToSlash(filepath.Join("lib", "router.dart"))
	raw, err := os.ReadFile(filepath.Join(root, rel))
	if err != nil {
		return fmt.Errorf("router: %w", err)
	}
	lines := strings.Split(string(raw), "\n")
	pages := routeBuilders(lines)

	for i, line := range lines {
		m := appRouteRe.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		meta := map[string]string{"constant": "AppRoutes." + m[1]}
		doc := docAbove(lines, i)
		if page, ok := pages[m[1]]; ok {
			meta["page"] = page
			if doc == "" {
				doc = "Renders " + page + "."
			}
		}
		b.node(Node{
			ID:    "app-route:" + m[2],
			Kind:  "app-route",
			Label: m[2],
			Layer: "app route",
			Path:  rel,
			Doc:   doc,
			Meta:  meta,
		})
	}
	return nil
}

var (
	routePathRe = regexp.MustCompile(`path:\s*AppRoutes\.(\w+)`)
	// [^=]* rather than .* so this stops at the builder's own arrow. Greedy matching
	// ran past it into the next GoRoute and gave /vault the JobsPage builder.
	routeBuilderRe = regexp.MustCompile(`builder:[^=]*=>\s*(?:const\s+)?(\w+)\s*\(`)
)

// routeBuilders maps each AppRoutes constant to the page its GoRoute builds. The two
// sit a few lines apart inside one GoRoute, so this pairs a path with the next
// builder it sees and drops the pairing at the following path. A builder whose arrow
// and page wrap onto separate lines still has to match, which is why it joins the
// following lines before testing.
func routeBuilders(lines []string) map[string]string {
	pages := map[string]string{}
	pending := ""
	for i, line := range lines {
		if m := routePathRe.FindStringSubmatch(line); m != nil {
			pending = m[1]
		}
		// A one-line GoRoute carries its path and builder together, so the path line
		// has to be tested for a builder too rather than skipped.
		if pending == "" || !strings.Contains(line, "builder:") {
			continue
		}
		end := min(i+3, len(lines))
		if m := routeBuilderRe.FindStringSubmatch(strings.Join(lines[i:end], " ")); m != nil {
			pages[pending] = m[1]
			pending = ""
		}
	}
	return pages
}

// docAbove returns the `///` block immediately above a line, at any indent, which is
// how the route constants inside AppRoutes are documented.
func docAbove(lines []string, idx int) string {
	end := idx
	for end > 0 && strings.HasPrefix(strings.TrimSpace(lines[end-1]), "///") {
		end--
	}
	if end == idx {
		return ""
	}
	block := make([]string, 0, idx-end)
	for _, l := range lines[end:idx] {
		block = append(block, strings.TrimSpace(l))
	}
	return firstParagraph(block)
}
