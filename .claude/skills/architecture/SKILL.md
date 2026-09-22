---
name: architecture
description: Answer questions about how Quark is built — its layers, where a feature lives, what an endpoint does, how a request flows, what the database holds, or how the Flutter app is wired. Use when asked to explain, map, diagram, or onboard someone onto this codebase, when starting work in an unfamiliar area, or when asked which routes, tables, or pages exist. Also use before claiming Quark does or does not do something.
---

# Quark architecture

The knowledge base for this codebase. Everything here is either prose someone maintains
or a fact derived from the tree at the moment you ask, so there is no generated graph to
go stale and no plugin to install.

Two halves:

- **Prose** — [`ARCHITECTURE.md`](../../../ARCHITECTURE.md) and
  [`docs/architecture/`](../../../docs/architecture/README.md) explain structure and intent,
  with Mermaid diagrams.
- **Derived facts** — `scripts/map.py` reads the router, the migrations and `lib/router.dart`
  and prints what is actually there.

When the two disagree, the code wins. Fix the prose in the same change.

## Start here

Read in this order and stop as soon as the question is answered. Do not open twenty files
when the answer is one table away.

| Question | Read |
| --- | --- |
| What is Quark, and what are its parts? | [`ARCHITECTURE.md`](../../../ARCHITECTURE.md) |
| How is the backend layered? What runs at startup? | [`docs/architecture/backend.md`](../../../docs/architecture/backend.md) |
| How does a request actually flow? | [`docs/architecture/request-flows.md`](../../../docs/architecture/request-flows.md) |
| What is stored, and where? | [`docs/architecture/data.md`](../../../docs/architecture/data.md) |
| How is the Flutter app wired? | [`docs/architecture/frontend.md`](../../../docs/architecture/frontend.md) |
| How do builds, generation and checks fit together? | [`docs/architecture/tooling.md`](../../../docs/architecture/tooling.md) |
| **Does Quark do X?** | [`docs/user-journeys/`](../../../docs/user-journeys/README.md) — the feature inventory, `JN-XXX` |
| Where does this file go? What will the checks reject? | [`AGENTS.md`](../../../AGENTS.md) |
| Which widgets are still coupled to the app? | [`lib/widgets/README.md`](../../../lib/widgets/README.md) |

`docs/user-journeys/` is the one to reach for before answering "can Quark …". The
architecture pages describe shape, not features, and guessing from shape is how you end up
describing a feature nobody built.

## Derived facts

```bash
python3 .claude/skills/architecture/scripts/map.py api    # every live route, its auth, its swagger entry
python3 .claude/skills/architecture/scripts/map.py db     # migrations, tables, sqlc queries
python3 .claude/skills/architecture/scripts/map.py app    # go_router routes, pages, controllers
```

`--json` on any of them for machine-readable output. `api --audit` prints only the
discrepancies and exits non-zero when it finds any:

- a live route with no swagger operation,
- a swagger operation with no live route,
- a handler package `routes.go` never mounts,
- a route declaration shape the script cannot read (teach it the new shape before trusting
  the counts).

The `api` map is the fastest way into the backend. It joins three things a reader otherwise
has to correlate by hand: the route table built from `internal/server/api/v0/**`, the auth
tier from `middleware.go` (`public` for `authExemptPaths`, `admin` for anything `routes.go`
mounts behind `RequireAdmin`, `user` otherwise), and the `@Summary` from the handler's
swagger godoc.

## Answering "how does X work?"

1. **Name the surface.** A URL, a screen, a button. `map.py api` or `map.py app` turns it
   into a file path.
2. **Read the handler.** It is three lines of real work: pull from the request, call a
   `pkg/util/<x>util` function, wrap the result. The handler tells you the shape; the
   service tells you the behavior.
3. **Read the service.** `pkg/util/<x>util/<x>.go` is the package's whole public surface by
   convention, so read that first and only then its helpers.
4. **Follow the writes.** File content goes through [`pkg/vfs`](../../../pkg/vfs). Persisted
   state goes through generated `internal/db` methods whose SQL lives in `sql/queries/`.
   Mutations publish on `deps.EventBus()`, which is what keeps open clients in sync.
5. **Cross the wire.** The Flutter side calls from `lib/services/`, is coordinated by a
   `ChangeNotifier` in `lib/controllers/`, and is rendered by `packages/quark_widgets`.

Trace it end to end before you explain it. A handler read on its own will tell you what is
returned and not what it cost.

## Answering "where does this go?"

`AGENTS.md` is normative and this skill does not restate it. The short version: handlers in
`internal/server/api/v0/<segment>/verb_noun.go`, business logic in `pkg/util/<x>util/`,
reusable visuals in `packages/quark_widgets`, app-coupled widgets in `lib/widgets/`. A new
router is dead until `setupRouters` in `internal/server/routes.go` mounts it.

## Keeping this honest

- Quote file paths as `path:line` so the reader can jump there.
- Say which source a claim came from, and say so plainly when a question is not answered by
  any of them rather than inferring from names.
- `map.py --audit` is the self-check. If it reports a shape it cannot read, the counts below
  it are under-reporting and the script needs teaching first.
- The script reads the tree, never a cache, so it is correct on a dirty working tree and on
  any branch.
