#! /usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: scripts/check-migration-numbers.bash [BASE_REF]

Checks the migrations under internal/db/migrations/ against BASE_REF
(default: $MIGRATION_BASE_REF, then origin/main):

  1. A migration that BASE_REF does not have is numbered above BASE_REF's
     highest. golang-migrate records one integer per database and only applies
     migrations above it, so a migration merged below main's highest is
     silently skipped on every device that has already upgraded (#1537).
  2. No two migrations share a number.
  3. Every migration has both an .up.sql and a .down.sql file, named
     NNN_snake_case.up.sql / NNN_snake_case.down.sql.
  4. The numbers run contiguously with no gaps, starting at 000 or 001, so
     the order a migration merged in is the order it is numbered in.
  5. The PostgreSQL set under internal/db/migrations_postgres/ is in step
     with it (#2958). That set starts at a baseline, its lowest number, which
     stands for every SQLite migration up to and including that number; above
     the baseline each engine has the same file names. A migration added for
     one engine without its counterpart fails here. Every PostgreSQL
     migration is named like a SQLite one and has both directions.

Untracked files count, so a local run catches a new migration before it is
committed. Exits 0 when clean, 1 with one line per violation otherwise.
USAGE
    exit 0
fi

BASE_REF="${1:-${MIGRATION_BASE_REF:-origin/main}}"
MIGRATIONS_DIR="internal/db/migrations"
POSTGRES_DIR="internal/db/migrations_postgres"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null; then
    echo "error: base ref '${BASE_REF}' does not resolve to a commit."
    echo "  Fetch it (git fetch origin main) or pass another ref as the first argument."
    exit 1
fi

name_pattern='^([0-9]+)_([a-z0-9_]+)\.(up|down)\.sql$'

declare -A base_names=()
base_max=-1
while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    name="$(basename "${path}")"
    base_names["${name}"]=1
    if [[ "${name}" =~ ${name_pattern} ]]; then
        number=$((10#${BASH_REMATCH[1]}))
        (( number > base_max )) && base_max=${number}
    fi
done < <(git ls-tree -r --name-only "${BASE_REF}" -- "${MIGRATIONS_DIR}")

declare -A number_owner=()
declare -A stems=()
declare -A directions=()
max_number=-1
min_number=-1
violations=0

report() {
    echo "$1"
    violations=$((violations + 1))
}

existing=()
added=()
while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    if [[ -n "${base_names[$(basename "${path}")]:-}" ]]; then
        existing+=("${path}")
    else
        added+=("${path}")
    fi
done < <(git ls-files --cached --others --exclude-standard -- "${MIGRATIONS_DIR}" | sort)

for path in "${existing[@]}" "${added[@]}"; do
    name="$(basename "${path}")"
    if [[ ! "${name}" =~ ${name_pattern} ]]; then
        report "${path}: not named NNN_snake_case.up.sql or NNN_snake_case.down.sql"
        continue
    fi
    number=$((10#${BASH_REMATCH[1]}))
    stem="${BASH_REMATCH[1]}_${BASH_REMATCH[2]}"
    direction="${BASH_REMATCH[3]}"
    stems["${stem}"]=1
    directions["${stem}.${direction}"]=1
    (( number > max_number )) && max_number=${number}
    (( min_number < 0 || number < min_number )) && min_number=${number}

    if [[ -z "${base_names[${name}]:-}" ]] && (( number <= base_max )); then
        printf -v padded '%03d' "${base_max}"
        report "${path}: numbered ${number}, at or below ${BASE_REF}'s highest migration (${padded}); renumber it above ${padded} or it will never run on an upgraded device"
    fi

    owner="${number_owner[${number}]:-}"
    if [[ -n "${owner}" && "${owner}" != "${stem}" ]]; then
        report "${path}: number ${number} is already used by ${owner}"
    else
        number_owner["${number}"]="${stem}"
    fi
done

for stem in "${!stems[@]}"; do
    [[ -n "${directions[${stem}.up]:-}" ]] || report "${MIGRATIONS_DIR}/${stem}.up.sql: missing (found only the .down.sql)"
    [[ -n "${directions[${stem}.down]:-}" ]] || report "${MIGRATIONS_DIR}/${stem}.down.sql: missing (found only the .up.sql)"
done

# Contiguity is anchored at the lowest number present rather than hard-coded to
# 000, because whether a set starts at 000 or 001 is a convention, not a
# correctness property -- golang-migrate only cares that versions increase. The
# floor is still pinned to 000 or 001 so the anchor cannot drift upward: without
# it, deleting the first few migrations would leave a set that is contiguous
# from wherever it now begins and passes silently.
if (( min_number > 1 )); then
    printf -v padded '%03d' "${min_number}"
    report "${MIGRATIONS_DIR}: lowest migration is ${padded}; numbering must start at 000 or 001"
fi

for (( number = min_number; number <= max_number; number++ )); do
    if [[ -z "${number_owner[${number}]:-}" ]]; then
        printf -v padded '%03d' "${number}"
        report "${MIGRATIONS_DIR}: no migration numbered ${padded} (numbering must be contiguous, with no gaps)"
    fi
done

# Rule 5: the PostgreSQL set against the SQLite one. The baseline is the
# lowest PostgreSQL number; everything above it pairs up by file name.
declare -A sqlite_files=()
for path in "${existing[@]}" "${added[@]}"; do
    sqlite_files["$(basename "${path}")"]=1
done
declare -A postgres_files=()
declare -A postgres_directions=()
baseline=-1
while IFS= read -r path; do
    [[ -n "${path}" ]] || continue
    name="$(basename "${path}")"
    if [[ ! "${name}" =~ ${name_pattern} ]]; then
        report "${path}: not named NNN_snake_case.up.sql or NNN_snake_case.down.sql"
        continue
    fi
    number=$((10#${BASH_REMATCH[1]}))
    postgres_files["${name}"]=${number}
    postgres_directions["${BASH_REMATCH[1]}_${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"]=1
    (( baseline < 0 || number < baseline )) && baseline=${number}
done < <(git ls-files --cached --others --exclude-standard -- "${POSTGRES_DIR}" | sort)

if (( baseline >= 0 )); then
    for key in "${!postgres_directions[@]}"; do
        stem="${key%.*}"
        [[ -n "${postgres_directions[${stem}.up]:-}" ]] || report "${POSTGRES_DIR}/${stem}.up.sql: missing (found only the .down.sql)"
        [[ -n "${postgres_directions[${stem}.down]:-}" ]] || report "${POSTGRES_DIR}/${stem}.down.sql: missing (found only the .up.sql)"
    done
    for name in "${!postgres_files[@]}"; do
        if (( postgres_files[${name}] > baseline )) && [[ -z "${sqlite_files[${name}]:-}" ]]; then
            report "${POSTGRES_DIR}/${name}: no ${MIGRATIONS_DIR}/${name}; a schema change is a migration in each set with the same name (internal/db/AGENTS.md)"
        fi
    done
    for name in "${!sqlite_files[@]}"; do
        [[ "${name}" =~ ${name_pattern} ]] || continue
        if (( 10#${BASH_REMATCH[1]} > baseline )) && [[ -z "${postgres_files[${name}]:-}" ]]; then
            report "${MIGRATIONS_DIR}/${name}: no ${POSTGRES_DIR}/${name}; a schema change is a migration in each set with the same name, even one that does nothing on that engine (internal/db/AGENTS.md)"
        fi
    done
fi

if (( violations > 0 )); then
    echo
    echo "${violations} migration violation(s) against ${BASE_REF}. See scripts/check-migration-numbers.bash --help."
    exit 1
fi

printf 'Migrations OK (highest on %s: %03d)\n' "${BASE_REF}" "${base_max}"
