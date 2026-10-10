#! /usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/frontend-test-shard.bash TOTAL_SHARDS SHARD_INDEX
       scripts/frontend-test-shard.bash check [WORKFLOW]

Splits the app suite (every test/**/*_test.dart) by file.

  TOTAL_SHARDS SHARD_INDEX  Print the test files of one shard, one per line.
                            SHARD_INDEX is 0-based. The sorted file list is
                            dealt out round-robin, so shards differ by at most
                            one file and each file lands in exactly one.
  check [WORKFLOW]          Read the TOTAL_SHARDS=<n> SHARD_INDEX=<i> legs out
                            of WORKFLOW (default .github/workflows/test.yml)
                            and fail unless they are indexes 0..n-1 of one n,
                            once each, and their files together are the whole
                            suite with nothing missing and nothing twice.

`flutter test --total-shards` splits the tests inside each file instead, so
every shard still compiles and loads every file (#3075). `make
test/unit/frontend/app TOTAL_SHARDS=<n> SHARD_INDEX=<i>` passes this script's
slice to `flutter test` instead.
USAGE
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

list_files() {
    find test -name '*_test.dart' | LC_ALL=C sort
}

shard_files() {
    list_files | awk -v total="$1" -v index_="$2" '(NR - 1) % total == index_'
}

check() {
    local workflow="$1"
    if [[ ! -f "${workflow}" ]]; then
        echo "error: ${workflow} not found. Pass the workflow that runs the shards as the second argument." >&2
        exit 1
    fi

    local legs
    legs="$(grep -oE 'TOTAL_SHARDS=[0-9]+ SHARD_INDEX=[0-9]+' "${workflow}" || true)"
    if [[ -z "${legs}" ]]; then
        echo "error: no 'TOTAL_SHARDS=<n> SHARD_INDEX=<i>' leg in ${workflow}." >&2
        echo "  If sharding was dropped on purpose, drop check/frontend/test-shards with it." >&2
        exit 1
    fi

    local totals total
    totals="$(sed -E 's/TOTAL_SHARDS=([0-9]+) .*/\1/' <<<"${legs}" | sort -u)"
    if [[ "$(wc -l <<<"${totals}")" -ne 1 ]]; then
        echo "error: the legs in ${workflow} disagree on TOTAL_SHARDS: $(tr '\n' ' ' <<<"${totals}")" >&2
        echo "  Give every app leg the same TOTAL_SHARDS." >&2
        exit 1
    fi
    total="${totals}"

    local have want
    have="$(sed -E 's/.*SHARD_INDEX=//' <<<"${legs}" | sort -n)"
    want="$(seq 0 $((total - 1)))"
    if [[ "${have}" != "${want}" ]]; then
        echo "error: ${workflow} runs SHARD_INDEX $(tr '\n' ' ' <<<"${have}")of TOTAL_SHARDS=${total}." >&2
        echo "  It needs one leg for each of 0..$((total - 1)), or part of the suite never runs." >&2
        exit 1
    fi

    local covered index
    covered="$(for index in ${have}; do shard_files "${total}" "${index}"; done | LC_ALL=C sort)"
    if ! diff <(list_files) <(echo "${covered}") >&2; then
        echo "error: the ${total} shards do not cover the suite exactly once ('<' is missing, '>' runs twice)." >&2
        echo "  Fix the split in scripts/frontend-test-shard.bash." >&2
        exit 1
    fi

    echo "${total} shards cover all $(list_files | wc -l) test files exactly once:"
    for index in ${have}; do
        echo "  shard ${index}: $(shard_files "${total}" "${index}" | wc -l) files"
    done
}

case "${1:-}" in
"" | -h | --help)
    usage
    ;;
check)
    check "${2:-.github/workflows/test.yml}"
    ;;
*)
    if [[ ! "$1" =~ ^[1-9][0-9]*$ || ! "${2:-}" =~ ^[0-9]+$ || "$2" -ge "$1" ]]; then
        echo "error: need TOTAL_SHARDS >= 1 and 0 <= SHARD_INDEX < TOTAL_SHARDS, got '$1' '${2:-}'." >&2
        echo "  Example: scripts/frontend-test-shard.bash 3 0" >&2
        exit 1
    fi
    shard_files "$1" "$2"
    ;;
esac
