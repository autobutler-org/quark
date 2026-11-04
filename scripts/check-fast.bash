#! /usr/bin/env bash
# cspell:words ACMRT toplevel

# Fast checks for the pre-commit hook. `make check` stays the full gate that
# CI and schmeide run. This one only looks at what the commit will contain.

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: scripts/check-fast.bash

Checks the files staged in this repository, and nothing else:

  1. gofmt, on each staged .go blob.
  2. dart format --set-exit-if-changed, on each staged .dart blob.
  3. cspell, on each staged blob, using this repo's cspell.json.

The blobs come from the index, so an unstaged edit is not what gets checked
and a staged file is still checked after the work tree copy changes.
Exits 0 when nothing is staged or every check passes. On failure, names the
fix: `make fix` for formatting, or .vscode/cspell.json for a word.

Run `make check/fast` to get the same. The pre-commit hook does.
USAGE
    exit 0
fi

QUARK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${REPO_ROOT}" ]]; then
    echo "check/fast: not a git repository. Run it from a checkout."
    exit 1
fi
cd "${REPO_ROOT}"

CSPELL="${QUARK_ROOT}/node_modules/.bin/cspell"
CONFIG="${QUARK_ROOT}/cspell.json"

list="$(mktemp)"
work=""
cleanup() {
    rm -f "${list}"
    if [[ -n "${work}" ]]; then
        rm -rf "${work}"
    fi
}
trap cleanup EXIT

# git diff exits 1 when there are differences. That is a result, not an error.
diff_status=0
git diff --cached --name-only --diff-filter=ACMRT -z >"${list}" || diff_status=$?
if [[ "${diff_status}" -gt 1 ]]; then
    echo "check/fast: could not list staged files (git diff --cached exited ${diff_status})."
    exit 1
fi
if [[ ! -s "${list}" ]]; then
    echo "check/fast: nothing staged."
    exit 0
fi

# TMPDIR on macOS already ends in a slash. A second one makes the shadow path
# `T//check-fast...`, which then does not match the prefix we try to strip
# out of tool output.
tmp="${TMPDIR:-/tmp}"
tmp="${tmp%/}"
work="$(mktemp -d "${tmp}/check-fast.XXXXXX")"
# cspell matches ignorePaths and gitignoreRoot against the directory it runs
# in. The shadow keeps the repo-relative paths, and the repo's gitignore, so
# a staged blob is checked the same way `make check/spelling` checks the tree.
if [[ -f .gitignore ]]; then
    cp .gitignore "${work}/.gitignore"
fi

failed=0
go_count=0
dart_count=0
spell_count=0

while IFS= read -r -d '' path; do
    [[ -z "${path}" ]] && continue
    mode="$(git ls-files --stage -- "${path}" | awk 'NR==1 { print $1 }')"
    # A submodule pointer or a symlink has no source to format. cspell would
    # read the link text, which is a path, not words.
    case "${mode}" in
        160000 | 120000) continue ;;
    esac
    if [[ -z "${mode}" ]]; then
        echo "check/fast: ${path} is in the staged diff but not in the index."
        failed=1
        continue
    fi
    if ! git checkout-index --prefix="${work}/" -- "${path}"; then
        echo "check/fast: could not read the staged copy of ${path}."
        failed=1
        continue
    fi
    case "${path}" in
        *.go)
            go_paths[${go_count}]="${path}"
            go_count=$((go_count + 1))
            ;;
        *.dart)
            dart_paths[${dart_count}]="${path}"
            dart_count=$((dart_count + 1))
            ;;
    esac
    spell_paths[${spell_count}]="${path}"
    spell_count=$((spell_count + 1))
done <"${list}"

if [[ "${go_count}" -gt 0 ]]; then
    if ! command -v gofmt >/dev/null 2>&1; then
        echo "check/fast: gofmt is not installed. Run 'make setup' first."
        failed=1
    else
        formatted="$(mktemp)"
        parse_error="$(mktemp)"
        bad_go_count=0
        i=0
        while [[ "${i}" -lt "${go_count}" ]]; do
            path="${go_paths[${i}]}"
            src="${work}/${path}"
            if ! gofmt "${src}" >"${formatted}" 2>"${parse_error}"; then
                echo "check/fast: gofmt could not parse ${path}:"
                cat "${parse_error}"
                echo "Fix: correct the syntax, then run 'make fix'."
                failed=1
            elif ! cmp -s "${src}" "${formatted}"; then
                bad_go[${bad_go_count}]="${path}"
                bad_go_count=$((bad_go_count + 1))
            fi
            i=$((i + 1))
        done
        rm -f "${formatted}" "${parse_error}"
        if [[ "${bad_go_count}" -gt 0 ]]; then
            echo "check/fast: these Go files are not gofmt-clean:"
            fix_cmd="gofmt -w"
            i=0
            while [[ "${i}" -lt "${bad_go_count}" ]]; do
                printf '  %s\n' "${bad_go[${i}]}"
                fix_cmd="${fix_cmd} $(printf '%q' "${bad_go[${i}]}")"
                i=$((i + 1))
            done
            echo "Fix: make fix"
            echo "     or: ${fix_cmd}"
            failed=1
        fi
    fi
fi

if [[ "${dart_count}" -gt 0 ]]; then
    if ! command -v dart >/dev/null 2>&1; then
        echo "check/fast: dart is not installed. Run 'make setup/flutter' first."
        failed=1
    else
        dart_srcs=()
        i=0
        while [[ "${i}" -lt "${dart_count}" ]]; do
            dart_srcs[${i}]="${work}/${dart_paths[${i}]}"
            i=$((i + 1))
        done
        dart_status=0
        dart_out="$(dart format --output=none --set-exit-if-changed "${dart_srcs[@]}" 2>&1)" || dart_status=$?
        if [[ "${dart_status}" -ne 0 ]]; then
            echo "check/fast: dart format would change staged Dart files:"
            # Drop the shadow directory so the line names the repo path.
            # Quoted removal is literal; a slash inside the path would end a
            # ${var//pat/} pattern early.
            prefix="${work}/"
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                if [[ "${line}" == *"${prefix}"* ]]; then
                    line="${line%%"${prefix}"*}${line#*"${prefix}"}"
                fi
                printf '%s\n' "${line}"
            done <<<"${dart_out}"
            echo "Fix: make fix"
            i=0
            while [[ "${i}" -lt "${dart_count}" ]]; do
                printf '     or: dart format %q\n' "${dart_paths[${i}]}"
                i=$((i + 1))
            done
            failed=1
        fi
    fi
fi

if [[ "${spell_count}" -gt 0 ]]; then
    if [[ ! -x "${CSPELL}" ]]; then
        echo "check/fast: cspell is not installed."
        echo "Fix: run 'npm ci' in the repo root (or 'make check/spelling' once), then commit again."
        failed=1
    elif [[ ! -f "${CONFIG}" ]]; then
        echo "check/fast: ${CONFIG} is missing, so cspell has no word list to use."
        failed=1
    else
        cspell_status=0
        cspell_out="$(
            cd "${work}"
            "${CSPELL}" --config "${CONFIG}" --no-config-search --no-progress --no-summary \
                --no-must-find-files "${spell_paths[@]}" 2>&1
        )" || cspell_status=$?
        if [[ "${cspell_status}" -ne 0 ]]; then
            echo "check/fast: cspell found a problem in a staged file."
            printf '%s\n' "${cspell_out}"
            echo "Fix: correct the spelling, or add the word to .vscode/cspell.json."
            failed=1
        fi
    fi
fi

exit "${failed}"
