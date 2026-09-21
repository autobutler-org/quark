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
			b.node(Node{
				ID:    "dart:" + rel,
				Kind:  "dart-file",
				Label: rel,
				Layer: dartLayer(rel),
				Path:  rel,
				Meta:  map[string]string{"package": pkgName},
			})

			raw, err := os.ReadFile(path)
			if err != nil {
				return err
			}
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
	for _, m := range appRouteRe.FindAllStringSubmatch(string(raw), -1) {
		b.node(Node{
			ID:    "app-route:" + m[2],
			Kind:  "app-route",
			Label: m[2],
			Layer: "app route",
			Path:  rel,
			Meta:  map[string]string{"constant": "AppRoutes." + m[1]},
		})
	}
	return nil
}
