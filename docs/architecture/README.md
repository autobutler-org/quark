# Architecture

Detailed architecture notes for Quark. The one-page summary is [`ARCHITECTURE.md`](../../ARCHITECTURE.md) at the
repository root; everything here expands on it. Diagrams are Mermaid, so GitHub renders them inline.

| Doc                                   | Covers                                                         |
| ------------------------------------- | -------------------------------------------------------------- |
| [System context](system-context.md)   | deployment, clients, storage devices, remote access            |
| [Backend](backend.md)                 | layers, startup, dependency graph, middleware, background work |
| [Request flows](request-flows.md)     | auth, streaming upload, live events, background jobs           |
| [Data](data.md)                       | SQLite databases, schema, VFS, the vault                       |
| [Frontend](frontend.md)               | Flutter app layers, routing, the widget package                |
| [Build and tooling](tooling.md)       | code generation, checks, how the knowledge base stays true     |

These pages describe structure, which changes slowly. For what Quark does feature by feature, the inventory is
[`docs/user-journeys/`](../user-journeys/README.md); for where files go and what the checks enforce, it is
[`AGENTS.md`](../../AGENTS.md). When a diagram here disagrees with the code, the code wins — fix the diagram.
