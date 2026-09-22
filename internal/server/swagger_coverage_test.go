package server

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/gin-gonic/gin"
)

// swaggerBasePath is the prefix every API route is mounted under, and the
// prefix the generated spec strips into its own basePath.
const swaggerBasePath = "/api/v0"

// ginParam rewrites gin's path parameters into the spec's braces: ":id" and the
// trailing wildcard "*filePath" both become "{...}".
var ginParam = regexp.MustCompile(`[:*]([A-Za-z_][A-Za-z0-9_]*)`)

// TestEveryMountedRouteIsInSwagger holds the generated spec to the routes the
// server actually serves.
//
// swag only reads an annotation block that sits directly above a named func. A
// handler written as an inline closure inside serverutil.ApiRoute has no godoc
// to attach one to, so swag skips the route silently, with no warning and no
// error — which is how 23 live routes went missing from the spec while every
// build stayed green (#2221). Anyone reading docs/swagger as the API inventory
// got it wrong, and Swagger UI offered no way to try them.
//
// Comparing the mounted routes against the spec is what makes that loud: a
// closure-shaped handler now fails here rather than quietly vanishing.
func TestEveryMountedRouteIsInSwagger(t *testing.T) {
	// A nil collector and an empty graph are fine: the routers are registered
	// at setup, and nothing here dispatches a request.
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	setupRouters(engine, nil, deputil.NewDependencies())

	raw, err := os.ReadFile(filepath.Join("..", "..", "docs", "swagger", "swagger.json"))
	if err != nil {
		t.Fatal(err)
	}
	var spec struct {
		BasePath string                                `json:"basePath"`
		Paths    map[string]map[string]json.RawMessage `json:"paths"`
	}
	if err := json.Unmarshal(raw, &spec); err != nil {
		t.Fatal(err)
	}
	if spec.BasePath != swaggerBasePath {
		t.Fatalf("basePath = %q, want %q", spec.BasePath, swaggerBasePath)
	}

	documented := make(map[string]bool, len(spec.Paths)*2)
	for path, ops := range spec.Paths {
		for method := range ops {
			documented[strings.ToUpper(method)+" "+path] = true
		}
	}

	var missing []string
	for _, route := range engine.Routes() {
		// Only the versioned API is specified; static and SPA routes are not.
		if !strings.HasPrefix(route.Path, swaggerBasePath+"/") {
			continue
		}
		specPath := ginParam.ReplaceAllString(strings.TrimPrefix(route.Path, swaggerBasePath), "{$1}")
		if key := route.Method + " " + specPath; !documented[key] {
			missing = append(missing, key)
		}
	}

	if len(missing) > 0 {
		t.Errorf(
			"%d mounted route(s) have no swagger operation:\n  %s\n\n"+
				"A handler written as an inline closure inside serverutil.ApiRoute cannot carry a\n"+
				"godoc block, so swag skips it. Give it a named func with an annotation block, then\n"+
				"re-run `make generate/backend/swagger`.",
			len(missing), strings.Join(missing, "\n  "),
		)
	}
}
