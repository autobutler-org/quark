package main

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

var (
	journeyRe = regexp.MustCompile(`(?m)^#{2,4}\s*(JN-[A-Z]+-\d+)\s*:\s*(.+?)\s*$`)
	// Paths the journeys write inline, as `/files` or `/files/:path`.
	journeyPathRe = regexp.MustCompile("`(/[a-zA-Z0-9_:/.-]*)`")
)

// collectJourneys reads docs/user-journeys/, the feature inventory AGENTS.md points
// at, and links each journey to the client routes its steps name.
func collectJourneys(root string, b *builder) error {
	files, err := filepath.Glob(filepath.Join(root, "docs", "user-journeys", "*.md"))
	if err != nil {
		return err
	}
	sort.Strings(files)

	for _, f := range files {
		base := filepath.Base(f)
		if base == "README.md" {
			continue
		}
		raw, err := os.ReadFile(f)
		if err != nil {
			return err
		}
		rel := filepath.ToSlash(filepath.Join("docs", "user-journeys", base))
		body := string(raw)
		locations := journeyRe.FindAllStringSubmatchIndex(body, -1)
		for i, loc := range locations {
			id := body[loc[2]:loc[3]]
			title := body[loc[4]:loc[5]]
			end := len(body)
			if i+1 < len(locations) {
				end = locations[i+1][0]
			}

			area := strings.TrimSuffix(base, ".md")
			b.node(Node{
				ID:    "journey:" + id,
				Kind:  "journey",
				Label: id,
				Layer: area,
				Path:  rel,
				Doc:   title,
				Meta:  map[string]string{"area": area},
			})
			for _, m := range journeyPathRe.FindAllStringSubmatch(body[loc[1]:end], -1) {
				b.edge("journey:"+id, "app-route:"+m[1], "visits")
			}
		}
	}
	return nil
}
