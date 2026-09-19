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
| `make understand`           | the Understand-Anything knowledge graph dashboard         |

## Knowledge graph (`make understand`)

`.ua/` holds a knowledge graph of the codebase produced by the
[Understand-Anything](https://github.com/Egonex-AI/Understand-Anything) Claude Code plugin: every file,
function and dependency, grouped into layers, with summaries and a guided tour. It is committed so anyone can
browse it without running the analysis; Go, Flutter and cspell all skip it.

```mermaid
flowchart LR
    src["cmd/ internal/ pkg/ sql/<br/>lib/ packages/*/lib"] -- "/understand<br/>(Claude Code plugin)" --> ua[".ua/<br/>knowledge-graph.json<br/>meta.json · config.json"]
    ignore[".ua/.understandignore"] -.-> ua
    ua -- symlinks --> site[".ua/site/ (gitignored)<br/>prebuilt dashboard"]
    rel(["GitHub release<br/>viewer tarball"]) -- "first run only" --> site
    site -- "python3 -m http.server" --> browser(["http://127.0.0.1:5173/?token=local"])
```

To view it:

```bash
make understand            # UA_PORT=8000 make understand to change the port
```

To regenerate it, install the plugin once and run the analysis from Claude Code in the repository root:

```text
/plugin marketplace add Egonex-AI/Understand-Anything
/plugin install understand-anything
/understand
```

Later runs are incremental — only files changed since the commit in `.ua/meta.json` are re-analyzed. The
scope is set by `.ua/.understandignore`, which excludes generated code, platform shells, tests and docs. The
static server cannot serve the source-code panel (the plugin's own `/understand-dashboard` can), but the graph,
search, layers and tours all work.
