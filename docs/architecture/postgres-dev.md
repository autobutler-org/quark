# PostgreSQL for local development

Quark's database is SQLite, and that is what every `make` target uses unless told otherwise. PostgreSQL is
being added as a second backend ([#2955](https://github.com/autobutler-org/quark/issues/2955)); this page is
how to run one locally and point the server and the tests at it.

> **Status.** The Makefile switch and the database are in place. The server does not read the setting yet:
> choosing the backend at startup is [#2957](https://github.com/autobutler-org/quark/issues/2957), and the
> PostgreSQL schema is [#2958](https://github.com/autobutler-org/quark/issues/2958). Until those land,
> `DB_BACKEND=postgres` starts a server that still opens SQLite, and `make` prints a note saying so.

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
make test/unit/backend DB_BACKEND=postgres
make test/integration/backend DB_BACKEND=postgres
make serve/docker DB_BACKEND=postgres          # the container image, joined to the compose network
```

To make it the default for your checkout, put `DB_BACKEND=postgres` in `.env`, which the Makefile includes.

With `DB_BACKEND=postgres` the Makefile hands the server two environment variables:

| Variable             | Value                                                             |
| -------------------- | ----------------------------------------------------------------- |
| `QUARK_DB_BACKEND`   | `postgres`                                                        |
| `QUARK_DATABASE_URL` | `postgres://quark:quark@127.0.0.1:5432/quark?sslmode=disable`     |

With `DB_BACKEND=sqlite` it sets neither, so a SQLite run is the same command it was before the switch existed.
`serve/docker` passes the same two with the host `postgres` in place of `127.0.0.1`, because a container
reaches the database over the compose network rather than the host's loopback.

If `DB_BACKEND=postgres` and nothing is listening on `127.0.0.1:5432`, the target stops before it builds
anything and prints the fix: `make serve/postgres`, or start Docker first. `make check/db DB_BACKEND=postgres`
runs that check on its own.

## The database

[`compose.yaml`](../../compose.yaml) runs one `postgres:17` container, for development only:

- user, password and database are all `quark`. The credentials are throwaway on purpose.
- the port is published on `127.0.0.1:5432` only, so nothing else on your network can reach it.
- data lives in the `quark_postgres` Docker volume and survives a restart.
- `pg_trgm`, which filename search needs, ships in the image. The schema enables it in its first migration
  (#2958), so there is no init script here to keep in step with the migrations.

| Target                     | What it does                                              |
| -------------------------- | --------------------------------------------------------- |
| `make serve/postgres`      | start it in the background and wait until it is healthy   |
| `make clean/postgres`      | stop it; the data stays                                   |
| `make clean/postgres/data` | stop it and delete the data                               |

To reset the database, run `make clean/postgres/data` and then `make serve/postgres`. `make clean` stops the
database too, and keeps its data.

If port 5432 is already taken by a PostgreSQL of your own, `make serve/postgres` fails to bind it. Stop the other
one; the port is fixed so that the Makefile, the compose file and this page agree on one URL.

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
