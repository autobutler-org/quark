# PostgreSQL for local development

Quark's database is SQLite, and that is what every `make` target uses unless told otherwise. PostgreSQL is
the second backend ([#2955](https://github.com/autobutler-org/quark/issues/2955)); this page is how to run one
locally and point the server and the tests at it.

> **Status.** The server chooses its backend at startup: `make serve/backend DB_BACKEND=postgres` starts one
> that connects to this database, migrates it and serves from it. Some features are not on PostgreSQL yet
> and say so when asked; [the data architecture page](data.md#what-does-not-work-on-postgresql-yet) lists each
> with its issue. The backend test suites still build their databases on SQLite whatever the switch says
> ([#2960](https://github.com/autobutler-org/quark/issues/2960)); see
> [What runs on PostgreSQL today](#what-runs-on-postgresql-today).

## Prerequisites

Docker with the Compose plugin (`docker compose`, v2). Docker Desktop includes it. `make check/docker/compose`
tells you whether yours does. Nothing else: no local PostgreSQL install, no `psql`.

## Two commands

```bash
make serve/postgres                      # start PostgreSQL in the background, wait until it accepts connections
make serve/backend DB_BACKEND=postgres   # run the server against it
```

`make serve/postgres` returns once the database is healthy, so the second command can follow it directly. It is
safe to run again when the database is already up.

## The switch

`DB_BACKEND` selects the database for every target that starts or tests the server. It accepts `sqlite` (the
default) and `postgres`; anything else stops `make` with a message naming the two.

```bash
make serve/backend                             # SQLite, as always
make serve/backend DB_BACKEND=postgres
make watch/backend DB_BACKEND=postgres         # the same with hot reload
make test/unit/backend DB_BACKEND=postgres     # adds the PostgreSQL tests; the rest still run on SQLite (#2960)
make test/integration/backend DB_BACKEND=postgres
make serve/docker DB_BACKEND=postgres          # the container image, joined to the compose network
```

To make it the default for your checkout, put `DB_BACKEND=postgres` in `.env`, which the Makefile includes.

With `DB_BACKEND=postgres` the Makefile hands the server two environment variables:

| Variable             | Value                                                             |
| -------------------- | ----------------------------------------------------------------- |
| `QUARK_DB_BACKEND`   | `postgres`                                                        |
| `QUARK_DATABASE_URL` | `postgres://quark:quark@127.0.0.1:5432/quark?sslmode=disable`     |

The server reads them in one place, `db.ConfigFromEnv`. A backend it does not know, or `postgres` with no
URL, stops it with a message naming what to set.

With `DB_BACKEND=sqlite` it sets neither, so a SQLite run is the same command it was before the switch existed.
`serve/docker` passes the same two with the host `postgres` in place of `127.0.0.1`, because a container
reaches the database over the compose network rather than the host's loopback. Its port is always 5432:
`POSTGRES_PORT` moves the port published on the host, not the one inside that network.

If `DB_BACKEND=postgres` and nothing is listening on `127.0.0.1:5432`, the target stops before it builds
anything and prints the fix: `make serve/postgres`, or start Docker first. `make check/db DB_BACKEND=postgres`
runs that check on its own.

## The database

[`compose.yaml`](../../compose.yaml) runs one `postgres:18` container, for development only:

- user, password and database are all `quark`. The credentials are throwaway on purpose.
- the port is published on `127.0.0.1:5432` only, so nothing else on your network can reach it.
- data lives in the `quark_postgres` Docker volume and survives a restart. The volume is mounted at
  `/var/lib/postgresql` and `PGDATA` is set to `/var/lib/postgresql/pgdata`, a layout images 17 and 18 both
  accept.
- `pg_trgm`, which filename search needs, ships in the image. The migration that adds filename search enables
  it (#2956), so there is no init script here to keep in step with the migrations.

| Target                     | What it does                                              |
| -------------------------- | --------------------------------------------------------- |
| `make serve/postgres`      | start it in the background and wait until it is healthy   |
| `make clean/postgres`      | stop it; the data stays                                   |
| `make clean/postgres/data` | stop it and delete the data                               |

To reset the database, run `make clean/postgres/data` and then `make serve/postgres`. `make clean` stops the
database too, and keeps its data.

### Image and port

Two variables change what runs. Pass them on the `make` command line, export them, or put them in `.env`, which
both the Makefile and `docker compose` read.

| Variable         | Default       | What it sets                                             |
| ---------------- | ------------- | -------------------------------------------------------- |
| `POSTGRES_IMAGE` | `postgres:18` | the image `compose.yaml` runs                            |
| `POSTGRES_PORT`  | `5432`        | the host port, for the container, the URL and `check/db` |

```bash
make serve/postgres POSTGRES_IMAGE=postgres:17
make serve/postgres POSTGRES_PORT=55432
make serve/backend DB_BACKEND=postgres POSTGRES_PORT=55432
```

`POSTGRES_PORT` has to reach every target that uses the database, not only `serve/postgres`, which is what
`.env` is for. If port 5432 is already taken by a PostgreSQL of your own, `make serve/postgres` fails to bind
it: set `POSTGRES_PORT` to a free one.

The default image is written once, in `compose.yaml`, so Renovate can move it. A data directory belongs to the
major version that created it, and PostgreSQL will not start on another's: after changing the major, whether
through `POSTGRES_IMAGE` or a Renovate bump, run `make clean/postgres/data` to start empty.

An image at 17 or older also gets an empty anonymous volume at `/var/lib/postgresql/data`, which those images
declare for themselves. Nothing is stored in it, and `make clean/postgres` leaves it behind; `docker volume
prune` clears those.

## What runs on PostgreSQL today

```bash
make serve/postgres
make test/db/postgres
```

`make test/db/postgres` runs every test that needs a real PostgreSQL against this database:

- **The query and schema layer** (`internal/db/...`). Every statement sqlc generated for PostgreSQL is
  prepared, the PostgreSQL schema is compared with the SQLite one column by column, the migrations run down
  and up again, and the queries are driven through `db.Querier`, the interface the rest of the backend holds.
- **Startup** (`internal/db`). An empty database is opened the way the server opens it
  (`db.ConnectToPostgres`): connect, migrate, and refuse a database that is dirty, from another build, or not
  Quark's, without changing it. Several starts at once on one database all come up.
- **Serving** (`internal/server`). `TestPostgresServesTheFirstRunAsSQLiteDoes` starts Quark on an empty
  PostgreSQL database through `deputil.DefaultDependencies`, mounts the real routers, and drives a first run
  over HTTP: setup, sign-in, creating and listing accounts, groups and albums, each one's duplicate, and a
  factory reset. It runs the same journey on SQLite and fails on any step the two answer differently, apart
  from the ones PostgreSQL refuses by design.
- **What differs at run time** (`pkg/util/sqlutil`, `pkg/util/searchutil`, `pkg/backup`). A unique violation
  is recognized from each engine's driver, the SQLite-only features, the chat and vault backups among them, are
  refused by name.

Each test creates a schema of its own and drops it, so your data is left alone.

The target names the backend itself and needs no `DB_BACKEND`. The same tests also run inside
`make test/unit/backend DB_BACKEND=postgres`; on the default backend they are skipped by name. Everything else
in the backend suites builds its database with `dbtest.NewDB`, which is SQLite on every backend until #2960. If no database
answers they fail and tell you to run `make serve/postgres`. CI runs the target in `test.yml`'s
`test-postgres` job, against a service container with the same image major and credentials as `compose.yaml`.

[`sql/queries/AGENTS.md`](../../sql/queries/AGENTS.md) has the rules for writing a query both engines accept,
and [`internal/db/AGENTS.md`](../../internal/db/AGENTS.md) the rules for the two schemas.

## Connecting with psql

With `psql` installed:

```bash
psql postgres://quark:quark@127.0.0.1:5432/quark
```

Without it, use the one inside the container:

```bash
docker compose exec postgres psql -U quark quark
```

## Both backends side by side

The two backends share nothing, so they can run at once. The SQLite database is a file in the server's data
directory; the PostgreSQL one is in the container. Leaving the database up costs a SQLite run nothing.

Two servers cannot both bind `:8080`, though. Run one from source and one from the container image on another
port:

```bash
make serve/backend                                         # SQLite on :8080
make serve/docker DB_BACKEND=postgres DOCKER_PORT=9000     # PostgreSQL on :9000
```

Tests have no port to collide on: run `make test/unit/backend` and then
`make test/unit/backend DB_BACKEND=postgres`.
