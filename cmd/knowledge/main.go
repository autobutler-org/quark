// Command knowledge builds a map of this repository out of the repository
// itself: Go packages and the imports between them, the HTTP routes in the swagger
// spec, the SQLite tables and the sqlc queries that touch them, the Flutter tree,
// and the user journeys. It writes one JSON file that docs/architecture/explorer.html
// renders, and can serve the two together.
//
// Everything it reads is already in the tree, so the graph regenerates offline and
// byte-for-byte: no network, no plugin, no timestamps.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
)

func main() {
	root := flag.String("root", ".", "repository root")
	out := flag.String("out", filepath.Join("docs", "architecture", "knowledge-graph.json"), "where to write the graph")
	serve := flag.Bool("serve", false, "serve the explorer instead of writing the graph")
	port := flag.Int("port", 5173, "port to serve on with -serve")
	flag.Parse()

	abs, err := filepath.Abs(*root)
	if err != nil {
		fail(err)
	}
	if _, err := os.Stat(filepath.Join(abs, "go.mod")); err != nil {
		fail(fmt.Errorf("%s is not the repository root: no go.mod", abs))
	}

	if *serve {
		if err := serveExplorer(abs, *out, *port); err != nil {
			fail(err)
		}
		return
	}

	graph, err := build(abs)
	if err != nil {
		fail(err)
	}
	if err := write(resolve(abs, *out), graph); err != nil {
		fail(err)
	}
	fmt.Printf("%s: %d nodes, %d edges\n", *out, len(graph.Nodes), len(graph.Edges))
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "knowledge:", err)
	os.Exit(1)
}

// resolve reads a path as relative to the repository root, leaving an absolute one alone.
func resolve(root, path string) string {
	if filepath.IsAbs(path) {
		return path
	}
	return filepath.Join(root, path)
}

// Graph is the whole map. Nodes and edges are sorted so a regeneration with no
// source change produces no diff.
type Graph struct {
	Nodes []Node `json:"nodes"`
	Edges []Edge `json:"edges"`
}

// Node is one thing in the repository: a Go package, a route, a table, a query, a
// Dart file, or a user journey.
type Node struct {
	ID    string            `json:"id"`
	Kind  string            `json:"kind"`
	Label string            `json:"label"`
	Layer string            `json:"layer"`
	Path  string            `json:"path,omitempty"`
	Doc   string            `json:"doc,omitempty"`
	Meta  map[string]string `json:"meta,omitempty"`
}

// Edge is a directed relationship. Kind is one of imports, handles, touches, or visits.
type Edge struct {
	From string `json:"from"`
	To   string `json:"to"`
	Kind string `json:"kind"`
}

// collector adds nodes and edges for one slice of the repository.
type collector func(root string, g *builder) error

type builder struct {
	nodes map[string]Node
	edges map[Edge]struct{}
}

func (b *builder) node(n Node) {
	if _, ok := b.nodes[n.ID]; !ok {
		b.nodes[n.ID] = n
	}
}

// edge records a relationship. Edges to nodes nobody collected are dropped at the
// end rather than here, because a collector may run before the node it points at.
func (b *builder) edge(from, to, kind string) {
	b.edges[Edge{From: from, To: to, Kind: kind}] = struct{}{}
}

func build(root string) (Graph, error) {
	b := &builder{nodes: map[string]Node{}, edges: map[Edge]struct{}{}}
	for _, c := range []collector{collectGoPackages, collectRoutes, collectData, collectDart, collectJourneys} {
		if err := c(root, b); err != nil {
			return Graph{}, err
		}
	}

	return b.graph(), nil
}

// graph drops edges whose endpoints nobody collected and sorts what is left, so the
// same tree always produces the same bytes.
func (b *builder) graph() Graph {
	g := Graph{}
	for _, n := range b.nodes {
		g.Nodes = append(g.Nodes, n)
	}
	for e := range b.edges {
		if _, ok := b.nodes[e.From]; !ok {
			continue
		}
		if _, ok := b.nodes[e.To]; !ok {
			continue
		}
		g.Edges = append(g.Edges, e)
	}
	sort.Slice(g.Nodes, func(i, j int) bool { return g.Nodes[i].ID < g.Nodes[j].ID })
	sort.Slice(g.Edges, func(i, j int) bool {
		if g.Edges[i].From != g.Edges[j].From {
			return g.Edges[i].From < g.Edges[j].From
		}
		if g.Edges[i].To != g.Edges[j].To {
			return g.Edges[i].To < g.Edges[j].To
		}
		return g.Edges[i].Kind < g.Edges[j].Kind
	})
	return g
}

func write(path string, g Graph) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	defer f.Close()

	enc := json.NewEncoder(f)
	enc.SetIndent("", "  ")
	enc.SetEscapeHTML(false)
	return enc.Encode(g)
}

// serveExplorer serves docs/architecture/ so the explorer can fetch the graph next
// to it. A file:// page cannot, which is the only reason a server is involved.
func serveExplorer(root, out string, port int) error {
	graph := resolve(root, out)
	if _, err := os.Stat(graph); err != nil {
		return fmt.Errorf("no graph at %s yet: run make generate/knowledge", out)
	}
	dir := filepath.Dir(graph)
	addr := fmt.Sprintf("127.0.0.1:%d", port)
	fmt.Printf("Knowledge explorer: http://%s/explorer.html\n", addr)
	return http.ListenAndServe(addr, http.FileServer(http.Dir(dir)))
}
