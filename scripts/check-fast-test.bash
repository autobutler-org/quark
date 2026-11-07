#! /usr/bin/env bash
# cspell:words gpgsign recieve

# Proves scripts/check-fast.bash checks the index, ignores unstaged edits, and
# names the fix. A fixture git repo keeps the real checkout's index alone.

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: scripts/check-fast-test.bash

Runs scripts/check-fast.bash against a temporary git repo: a clean index
passes, an unformatted or misspelled staged blob fails and names the fix,
and the same defect left unstaged does not. Also checks the pre-commit hook
calls `make check/fast` and that `make help` lists the target.

Run `make test/check/fast` to get the same.
USAGE
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO_ROOT}/scripts/check-fast.bash"
HOOK="${REPO_ROOT}/git/hooks/pre-commit"

for cmd in gofmt dart git; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "check-fast-test: ${cmd} is not installed. Run 'make setup' first."
        exit 1
    fi
done
if [[ ! -x "${REPO_ROOT}/node_modules/.bin/cspell" ]]; then
    echo "check-fast-test: cspell is not installed. Run 'npm ci' (or 'make test/check/fast') first."
    exit 1
fi

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/check-fast-test.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT

git -C "${FIXTURE}" init -q -b main
git -C "${FIXTURE}" config user.email "check-fast@example.com"
git -C "${FIXTURE}" config user.name "check-fast"
git -C "${FIXTURE}" config commit.gpgsign false

failures=0

# expect EXIT TEXT FORBIDDEN LABEL runs the check in the fixture.
expect() {
    local want_exit="$1" want_text="$2" forbid="$3" label="$4" out code=0
    out="$("${SCRIPT}" 2>&1)" || code=$?
    if [[ "${code}" -ne "${want_exit}" ]]; then
        echo "FAIL ${label}: exit ${code}, want ${want_exit}"
        printf '%s\n' "${out}" | sed 's/^/    /'
        failures=$((failures + 1))
        return
    fi
    if [[ -n "${want_text}" && "${out}" != *"${want_text}"* ]]; then
        echo "FAIL ${label}: output missing '${want_text}'"
        printf '%s\n' "${out}" | sed 's/^/    /'
        failures=$((failures + 1))
        return
    fi
    if [[ -n "${forbid}" && "${out}" == *"${forbid}"* ]]; then
        echo "FAIL ${label}: output unexpectedly contains '${forbid}'"
        printf '%s\n' "${out}" | sed 's/^/    /'
        failures=$((failures + 1))
        return
    fi
    echo "ok ${label}"
}

fresh() {
    cd "${FIXTURE}"
    git rm -rf --quiet --cached . >/dev/null 2>&1 || true
    find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
}

cd "${FIXTURE}"
expect 0 "nothing staged" "" "nothing staged"

fresh
mkdir -p "dir"
printf 'package p\nfunc F(){ }\n' >"dir/spaced name.go"
git add -- "dir/spaced name.go"
expect 1 "make fix" "" "unformatted staged go file"
expect 1 "dir/spaced name.go" "" "unformatted go file is named"

fresh
printf 'package p\n\nfunc F() {}\n' >good.go
gofmt -w good.go
git add -- good.go
printf 'package p\nfunc G(){ }\n' >bad.go
expect 0 "" "not gofmt-clean" "unstaged go file is ignored"

fresh
printf 'package p\n\nfunc F() {}\n' >sample.go
gofmt -w sample.go
git add -- sample.go
printf 'package p\nfunc F(){ }\n' >sample.go
expect 0 "" "not gofmt-clean" "gofmt reads the index, not the work tree"

fresh
mkdir -p lib
printf 'void main(){print("hi");}\n' >lib/main.dart
git add -- lib/main.dart
expect 1 "make fix" "" "unformatted staged dart file"
expect 1 "lib/main.dart" "" "unformatted dart file is named"

# Formatted under the repo's language version (pubspec's sdk lower bound),
# which the SDK's newest style would re-wrap.
fresh
mkdir -p lib
cat >lib/typedef.dart <<'DART'
typedef DeleteFilesFn =
    Future<void> Function(
      List<String> filePaths, {
      String? rootDir,
      String? deviceSerial,
    });
DART
git add -- lib/typedef.dart
expect 0 "" "dart format would change" "dart format uses the repo's language version"

fresh
printf 'Please recieve this.\n' >note.md
git add -- note.md
printf 'Please receive this.\n' >note.md
expect 1 ".vscode/cspell.json" "" "cspell reads the index, not the work tree"

fresh
printf 'Hello from the fixture.\n' >note.md
git add -- note.md
expect 0 "" "cspell found" "staged spelling that is clean"

if grep -q '"\${MAKE}" check/fast' "${HOOK}"; then
    echo "ok hook runs check/fast"
else
    echo "FAIL hook does not run check/fast"
    failures=$((failures + 1))
fi
if grep -Eq '"\$\{MAKE\}" check([^/]|$)' "${HOOK}"; then
    echo "FAIL hook still runs the full check"
    failures=$((failures + 1))
else
    echo "ok hook does not run the full check"
fi

if command -v gmake >/dev/null 2>&1; then
    MAKE=gmake
else
    MAKE=make
fi
# Capture help instead of piping to grep -q. grep -q exits at the first match,
# make gets SIGPIPE, and pipefail then reports the pipeline as failed.
help_out="$("${MAKE}" -C "${REPO_ROOT}" help 2>&1)" || true
if [[ "${help_out}" == *"check/fast"* && "${help_out}" == *"test/check/fast"* ]]; then
    echo "ok make help lists check/fast"
else
    echo "FAIL make help does not list check/fast"
    failures=$((failures + 1))
fi

if [[ "${failures}" -ne 0 ]]; then
    echo "check-fast-test: ${failures} failed"
    exit 1
fi
echo "check-fast-test: all passed"
