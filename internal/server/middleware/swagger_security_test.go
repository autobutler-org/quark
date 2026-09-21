package middleware

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// TestSwaggerSecurityMatchesAuthExemptPaths holds the generated spec to the auth
// middleware. Swagger UI only offers a token for operations that declare one, so a
// handler that forgets `@Security BearerAuth` gets a Try-it-out that can only 401 (#2209).
func TestSwaggerSecurityMatchesAuthExemptPaths(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "..", "..", "docs", "swagger", "swagger.json"))
	if err != nil {
		t.Fatal(err)
	}
	var spec struct {
		BasePath            string `json:"basePath"`
		SecurityDefinitions map[string]struct {
			Type string `json:"type"`
			In   string `json:"in"`
			Name string `json:"name"`
		} `json:"securityDefinitions"`
		Paths map[string]map[string]struct {
			Security []map[string][]string `json:"security"`
		} `json:"paths"`
	}
	if err := json.Unmarshal(raw, &spec); err != nil {
		t.Fatal(err)
	}

	if spec.BasePath != "/api/v0" {
		t.Errorf("basePath = %q, want /api/v0", spec.BasePath)
	}
	bearer, ok := spec.SecurityDefinitions["BearerAuth"]
	if !ok || bearer.Type != "apiKey" || bearer.In != "header" || bearer.Name != "Authorization" {
		t.Errorf("BearerAuth definition = %+v, want an apiKey in the Authorization header", bearer)
	}

	for path, ops := range spec.Paths {
		exempt := authExemptPaths[spec.BasePath+path]
		for method, op := range ops {
			secured := false
			for _, requirement := range op.Security {
				if _, ok := requirement["BearerAuth"]; ok {
					secured = true
				}
			}
			switch {
			case exempt && secured:
				t.Errorf("%s %s is in authExemptPaths but its godoc declares @Security BearerAuth", method, path)
			case !exempt && !secured:
				t.Errorf("%s %s needs a session but its godoc has no @Security BearerAuth", method, path)
			}
		}
	}
}
