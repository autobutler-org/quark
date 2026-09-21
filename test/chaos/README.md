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

Auth-dependent cases skip when credentials/token are unset. Do not commit real
credentials.

The backend must have finished `/api/v0/auth/setup`: until it has, the auth
middleware lets every `/api` route through, and `TestEdgeProtectedWithoutAuth`
skips. `make test/chaos/local` runs setup before the suite.

## Run

Against a temporary backend that is built, set up, and torn down for you
(this is what CI runs):

```bash
make test/chaos/local
```

With a local backend already up:

```bash
# recommended
make test/chaos

# or
go test -tags chaos -count=1 -timeout 10m ./test/chaos/
```

Against another host/port:

```bash
QUARK_BASE_URL=http://127.0.0.1:8081 make test/chaos
```

With optional auth (for endpoints that return 401 without a session):

```bash
QUARK_USER=... QUARK_PASSWORD=... make test/chaos
# or
QUARK_ACCESS_TOKEN=... make test/chaos
```

## CI / unit tests

All Go files here use `//go:build chaos`, so they are **excluded** from
ordinary `go test ./...` / `make test/unit`. Only `make test/chaos` (or an
explicit `-tags chaos` invocation) runs them.

If the backend is unreachable, every test fails with a message naming the URL
and how to start a backend, so a server that never came up cannot pass as a run
of skipped tests.

`make test/chaos/local` is the CI entry point (the `api-chaos` job in
`.github/workflows/ci-backend.yml`).

## Auth sequencing / rate limits

Login endpoints are per-IP rate limited (~5 rps, burst 10). Invalid-login
bursts are **expected** to return `429`; that is a product success for the
chaos case, not a suite failure.

The suite keeps authenticated cases independent of that burst:

1. `TestMain` warms a shared session when `QUARK_USER`/`QUARK_PASSWORD` or
   `QUARK_ACCESS_TOKEN` is set, before any test runs.
2. Authenticated cases reuse that session (or `QUARK_ACCESS_TOKEN`) and do not
   re-login after the burst.
3. Invalid-login / mixed login bursts live in `zz_login_bursts_test.go`. Go runs
   tests in file order, then declaration order, so that file runs last; keep
   its name sorting last.
4. If a login is still needed and sees `429`, the helper retries with backoff.

You can also supply `QUARK_ACCESS_TOKEN` / `QUARK_TOKEN` to skip password login
entirely.

## Expected behaviors

| Scenario | Acceptable outcomes |
| --- | --- |
| Oversized JSON / long strings | `400`, `401`, `413`, `429`, or connection reset / client timeout — **not** a cascade of `5xx` |
| Any case | **not** `404`: a missing route means the case tested nothing, so it fails |
| Empty / whitespace / unicode edge inputs | `400` / `401` / `422` / empty success body — **not** `5xx` storms |
| Concurrent bursts on public endpoints | Mostly `2xx`/`4xx`/`429`; `5xx` rate must stay below the documented threshold |
| Invalid-login burst | Mostly `401` / `429` — **`429` is OK and expected** under rate limiting |
| Unauthenticated protected routes | `401` (or skip when probing only public paths) |

## Non-goals

- No privilege-escalation recipes, exploit PoCs, or attack playbooks
- `make test/chaos` never starts or stops a backend; `make test/chaos/local`
  starts its own on `PERF_PORT` (18080) and stops only that one
- Does not replace `test/performance` wrk load profiles; complements them with API-shape chaos

## Related

- `test/performance/` — wrk throughput/load profiles (spins its own temporary server via Make)
- `make test/integration` — in-process Gin integration tests under `internal/server/api/v0/`
