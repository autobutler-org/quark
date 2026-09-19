# API stress / chaos suite (defensive QA)

Reusable resilience checks against a running Quark backend (`quark serve` /
`make watch/backend`). This is **defensive QA only**: oversized and weird
inputs, concurrent bursts, and graceful-failure expectations. It is not an
exploit harness and does not include attack procedures.

## Requirements

- Go toolchain matching `go.mod`
- A reachable backend (default `http://127.0.0.1:8080`)

## Environment

| Variable | Purpose |
| --- | --- |
| `QUARK_BASE_URL` | Base URL (default `http://127.0.0.1:8080`) |
| `QUARK_USER` or `QUARK_USERNAME` | Optional username for authenticated cases |
| `QUARK_PASSWORD` | Optional password |
| `QUARK_ACCESS_TOKEN` / `QUARK_TOKEN` | Optional bearer/session token (skips login) |
| `QUARK_STRESS_TIMEOUT` | Per-request timeout (default `30s`) |
| `QUARK_STRESS_OVERSIZE_BYTES` | Oversized payload size (default `2097152` ≈ 2 MiB) |
| `QUARK_STRESS_CONCURRENCY` | Concurrent workers (default `32`) |
| `QUARK_STRESS_BURSTS` | Requests per goroutine (default `8`) |

Auth-dependent cases **skip cleanly** when credentials/token are unset.
Do not commit real credentials.

## Run

With a local backend already up:

```bash
# recommended
make test/stress

# or
go test -tags stress -count=1 -timeout 10m ./tests/stress/
```

Against another host/port:

```bash
QUARK_BASE_URL=http://127.0.0.1:8081 make test/stress
```

With optional auth (for endpoints that return 401 without a session):

```bash
QUARK_USER=... QUARK_PASSWORD=... make test/stress
# or
QUARK_ACCESS_TOKEN=... make test/stress
```

## CI / unit tests

All Go files here use `//go:build stress`, so they are **excluded** from
ordinary `go test ./...` / `make test/unit`. Only `make test/stress` (or an
explicit `-tags stress` invocation) runs them.

If the backend is unreachable, the suite fails the readiness probe with a
clear skip/fail message rather than hanging forever.

## Expected behaviors

| Scenario | Acceptable outcomes |
| --- | --- |
| Oversized JSON / long strings | `400`, `401`, `413`, `429`, or connection reset / client timeout — **not** a cascade of `5xx` |
| Empty / whitespace / unicode edge inputs | `400` / `401` / `422` / empty success body — **not** `5xx` storms |
| Concurrent bursts on public endpoints | Mostly `2xx`/`4xx`/`429`; `5xx` rate must stay below the documented threshold |
| Unauthenticated protected routes | `401` (or skip when probing only public paths) |

## Non-goals

- No privilege-escalation recipes, exploit PoCs, or attack playbooks
- Does not start or stop the backend (will not kill processes on `:8080`/`:8081`/`:8000`)
- Does not replace `test/performance` wrk load profiles; complements them with API-shape chaos

## Related

- `test/performance/` — wrk throughput/load profiles (spins its own temporary server via Make)
- `make test/integration` — in-process Gin integration tests under `internal/server/api/v0/`
