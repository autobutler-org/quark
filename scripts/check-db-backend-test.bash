#! /usr/bin/env bash

# This script proves the Makefile's DB_BACKEND switch does what
# docs/architecture/postgres-dev.md says: an unknown backend is refused with a message
# naming the two real ones, sqlite leaves the server recipes as they were, and postgres
# reaches them. It reads recipes with `make --dry-run`, so it starts nothing and needs
# neither Docker nor a database.

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: scripts/check-db-backend-test.bash [make]

Checks the Makefile's DB_BACKEND switch by dry-running targets with the given make
(default: make). Run `make test/db-backend` to get the same.
USAGE
    exit 0
fi

MAKE_BIN="${1:-make}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() {
    echo "check-db-backend-test: $1" >&2
    exit 1
}

# recipe TARGET [VAR=value...] prints the commands make would run for TARGET alone.
# Its prerequisites are marked up to date (-o) so their recipes stay out of the output.
recipe() {
    "${MAKE_BIN}" --dry-run --no-print-directory -o check/db -o generate/backend -o build/backend \
        -o check/docker -o internal/server/public/stub.txt "$@"
}

if out="$("${MAKE_BIN}" --dry-run check/db DB_BACKEND=mysql 2>&1)"; then
    fail "DB_BACKEND=mysql was accepted"
fi
[[ "${out}" == *"DB_BACKEND=sqlite"* && "${out}" == *"DB_BACKEND=postgres"* ]] ||
    fail "the DB_BACKEND=mysql error does not list sqlite and postgres: ${out}"

"${MAKE_BIN}" check/db >/dev/null || fail "check/db failed with the default backend"
"${MAKE_BIN}" check/db DB_BACKEND=sqlite >/dev/null || fail "check/db failed with DB_BACKEND=sqlite"

for target in serve/backend serve/backend/secure watch/backend watch/backend/secure serve/docker; do
    # Captured before matching: grep -q on a pipe closes it early, and pipefail then
    # reports make's SIGPIPE as a failure.
    default="$(recipe "${target}")"
    postgres="$(recipe "${target}" DB_BACKEND=postgres)"
    [[ "${default}" != *QUARK_DB_BACKEND* && "${default}" != *QUARK_DATABASE_URL* ]] ||
        fail "${target} passes a database setting with the default backend"
    [[ "${postgres}" == *QUARK_DB_BACKEND=postgres* ]] ||
        fail "${target} DB_BACKEND=postgres does not pass QUARK_DB_BACKEND=postgres"
    [[ "${postgres}" == *QUARK_DATABASE_URL=*postgres://* ]] ||
        fail "${target} DB_BACKEND=postgres does not pass QUARK_DATABASE_URL"
done

# The test targets get the setting from the exported environment rather than the recipe.
env_of() {
    "${MAKE_BIN}" --no-print-directory --eval 'print-db-env: ; @env | grep "^QUARK_D" || true' print-db-env "$@"
}
[[ -z "$(env_of)" ]] || fail "the default backend exports a database setting: $(env_of)"
[[ "$(env_of DB_BACKEND=postgres)" == *"QUARK_DB_BACKEND=postgres"* ]] ||
    fail "DB_BACKEND=postgres does not export QUARK_DB_BACKEND"

database="$("${MAKE_BIN}" --dry-run --print-data-base check/db 2>/dev/null)"
for target in serve/backend serve/backend/secure watch/backend watch/backend/secure serve/docker \
    test/unit/backend test/integration/backend; do
    grep -q "^${target}:.*check/db" <<<"${database}" || fail "${target} does not depend on check/db"
done

echo "check-db-backend-test: ok"
