# Build and tooling

Everything runs through the Makefile (`make help` lists it). This page shows how the pieces feed each other; the
rules for using them are in [`AGENTS.md`](../../AGENTS.md).

## Code generation

Generated files are committed, and CI regenerates them and fails on any diff.

```mermaid
flowchart LR
    migrations["internal/db/migrations/*.sql"] --> sqlc{{sqlc}}
    queries["sql/queries/*.sql"] --> sqlc --> sqlcCode["internal/db/*.sql.go"]
    annotations["handler godoc<br/>@Summary @Router …"] --> swag{{swag}} --> swagger["docs/swagger/"]
    svgs["packages/quark_icons/svgs"] --> icons{{generate/frontend/quark-icons}} --> font["icon font + Dart"]
    widgetComments["quark_widgets /// docs"] --> wd{{generate/frontend/widget-docs}} --> widgetDocs["docs.g.dart"]
    deps["go.mod · pubspec"] --> sbom{{generate/frontend/sbom}} --> sbomFiles["assets/sbom_*.json"]
    lib["lib/ + packages/"] --> web{{build/frontend/web}} --> public["internal/server/public/"]
    public -- "//go:embed" --> binary[["quark binary"]]
    sqlcCode --> binary
    swagger --> binary
```

## Checks

```mermaid
flowchart TB
    check["make check<br/>(pre-commit hook and CI)"]
    check --> be["check/backend<br/>gofmt · golangci-lint · check-go-structure.bash · sqlc vet · generate diff"]
    check --> fe["check/frontend<br/>dart format · flutter analyze · generate diff"]
    check --> sp["check/spelling<br/>cspell + .vscode/cspell.json allowlist"]
    ci["CI only"] --> mig["check/migrations"]
    ci --> vuln["govulncheck"]
    ci --> cross["cross-compile darwin/arm64, linux/arm64"]
```

## Running locally

| Target                      | Serves                                                   |
| --------------------------- | -------------------------------------------------------- |
| `make watch/backend`        | backend with hot reload (air), HTTP on `:8080`           |
| `make watch/backend/secure` | the same over HTTPS on `:443`, self-signed               |
| `make serve/frontend`       | Flutter web dev server pointed at the backend            |
| `make serve/knowledge`      | the architecture explorer on `:5173`                     |

## Knowledge base

There is no committed graph to keep in sync. The knowledge base is these pages plus the
`architecture` skill in [`.claude/skills/architecture/`](../../.claude/skills/architecture/SKILL.md),
which tells an agent which source answers which question and ships a script that derives the
rest from the tree on demand.

```mermaid
flowchart LR
    subgraph maintained["Maintained by hand"]
        arch["ARCHITECTURE.md<br/>docs/architecture/"]
        journeys["docs/user-journeys/<br/>JN-XXX feature inventory"]
        agents["AGENTS.md<br/>conventions and checks"]
    end
    subgraph derived["Derived on demand"]
        api["map.py api<br/>routes · auth tier · swagger entry"]
        db["map.py db<br/>migrations · tables · sqlc queries"]
        app["map.py app<br/>go_router · pages · controllers"]
    end
    src["internal/server/api/**<br/>middleware.go · routes.go"] --> api
    mig["internal/db/migrations/<br/>sql/queries/"] --> db
    dart["lib/router.dart<br/>lib/pages · lib/controllers"] --> app
    skill(["/architecture skill"]) --> maintained
    skill --> derived
```

Because the script reads the tree rather than a cache, it is right on a dirty working tree
and on any branch:

```bash
python3 .claude/skills/architecture/scripts/map.py api
python3 .claude/skills/architecture/scripts/map.py db
python3 .claude/skills/architecture/scripts/map.py app
```

`map.py api --audit` is the one that catches drift. It exits non-zero when a live route has
no swagger operation, when swagger carries an operation no router serves, when a handler
package is never mounted, or when a route is declared in a shape the script cannot read.

Swag only reads an annotation block that sits directly above a named `func`. A handler
written as an inline closure inside `var xRoute = serverutil.ApiRoute(...)` is skipped
silently, annotations and all — which is why `--audit` compares against the router rather
than trusting `docs/swagger/` to be complete.

### Browsing it

`make serve/knowledge` puts the same tree in front of a person rather than an agent. `cmd/knowledge` reads it
once — `go list -json ./...` for Go packages and their imports, the swagger spec for routes, the migrations and
`sql/queries/` for tables and queries, `lib/` and each `packages/*/lib/` for Dart files and their imports, and
`docs/user-journeys/` for the journeys — and `docs/architecture/explorer.html` renders the result: search,
filter by kind, click a node, and walk its edges in either direction.

```bash
make serve/knowledge       # KNOWLEDGE_PORT=8000 to move it off :5173
make generate/knowledge    # just docs/architecture/knowledge-graph.json, for jq
```

The graph is a build output, gitignored and rebuilt in a couple of seconds, so it holds to the rule above: no
cache to go stale. It overlaps `map.py` on routes, tables and client routes, and adds what an explorer needs
that a one-shot query does not — the import graph on both sides, and the edges between routes, handlers,
queries, tables and journeys.
