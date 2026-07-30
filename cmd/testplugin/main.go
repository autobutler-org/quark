// testplugin is a minimal AutoButler plugin binary for testing the plugin
// subprocess host (Phase 4a). It:
//
//  1. Listens on a random loopback port.
//  2. Writes "READY addr=<host:port>" to stdout.
//  3. Serves GET /health → 200 OK.
//  4. Serves GET /manifest → JSON PluginManifest.
//
// Usage:
//
//	testplugin --addr 127.0.0.1:0 --plugin-id hello-world
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:0", "listen address (port 0 = random)")
	pluginID := flag.String("plugin-id", "hello-world", "plugin identifier")
	flag.Parse()

	// Override addr from env if set.
	if env := os.Getenv("AUTOBUTLER_PLUGIN_ADDR"); env != "" {
		*addr = env
	}
	if env := os.Getenv("AUTOBUTLER_PLUGIN_ID"); env != "" {
		*pluginID = env
	}

	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "testplugin: listen: %v\n", err)
		os.Exit(1)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/manifest", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"id":          *pluginID,
			"name":        "Hello World Plugin",
			"version":     "0.1.0",
			"description": "A minimal test plugin for the AutoButler plugin host.",
		})
	})
	mux.HandleFunc("/hello", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"message": "Hello from " + *pluginID})
	})

	// Announce readiness on stdout — the host is waiting for this line.
	fmt.Printf("READY addr=%s\n", ln.Addr().String())

	if err := http.Serve(ln, mux); err != nil {
		fmt.Fprintf(os.Stderr, "testplugin: serve: %v\n", err)
		os.Exit(1)
	}
}
