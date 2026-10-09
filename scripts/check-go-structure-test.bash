#! /usr/bin/env bash

# This script proves scripts/check-go-structure.bash still bites. It builds a small
# fixture module in a temp directory, checks the script passes it clean, then adds one
# violation of each file-access rule at a time and checks the script fails it with the
# message naming the fix. A check that silently stopped matching would otherwise pass
# the real tree forever.

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: scripts/check-go-structure-test.bash

Runs scripts/check-go-structure.bash against a fixture module: once clean, which
must pass, and once per planted violation, which must fail naming the fix.
Run `make test/structure/go` to get the same.
USAGE
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/check-go-structure.XXXXXX")"
trap 'rm -rf "${FIXTURE}"' EXIT

MODULE="github.com/autobutler-org/quark"
mkdir -p "${FIXTURE}/scripts"
cp "${REPO_ROOT}/scripts/check-go-structure.bash" "${FIXTURE}/scripts/"
printf 'module %s\n\ngo 1.22\n' "${MODULE}" >"${FIXTURE}/go.mod"

# write PATH reads a Go file from stdin into the fixture.
write() {
    mkdir -p "$(dirname "${FIXTURE}/$1")"
    cat >"${FIXTURE}/$1"
}

# A storageutil with the files directory, a vfs with a host path, and a handler that
# does nothing it should not: the shape the rules look at, and nothing else.
write pkg/util/storageutil/storageutil.go <<'GO'
// Package storageutil is the fixture's stand-in.
package storageutil

// GetFilesDir is where the files directory is.
func GetFilesDir() (string, error) { return "", nil }
GO
write pkg/vfs/vfs.go <<'GO'
// Package vfs is the fixture's stand-in.
package vfs

// HostPather turns a namespace path into a host path.
type HostPather interface {
	HostPath(path string) (string, error)
}
GO
write pkg/util/fileutil/fileutil.go <<'GO'
// Package fileutil is the fixture's stand-in.
package fileutil

// Nothing does nothing.
func Nothing() {}
GO
write internal/server/api/v0/files/files.go <<'GO'
// Package v0_files is the fixture's stand-in.
package v0_files

// Nothing does nothing.
func Nothing() {}
GO

failures=0

# expect WANT_EXIT WANT_TEXT LABEL runs the check and compares.
expect() {
    local want_exit="$1" want_text="$2" label="$3" out code=0
    out="$("${FIXTURE}/scripts/check-go-structure.bash" 2>&1)" || code=$?
    if [[ "${code}" -ne "${want_exit}" || "${out}" != *"${want_text}"* ]]; then
        echo "FAIL ${label}: exit ${code}, want ${want_exit} with '${want_text}'; output:"
        echo "${out}" | sed 's/^/    /'
        failures=$((failures + 1))
    else
        echo "ok   ${label}"
    fi
}

# plant PATH WANT_EXIT WANT_TEXT LABEL writes a file from stdin, runs the check,
# and takes the file out again so each case stands alone.
plant() {
    write "$1"
    expect "$2" "$3" "$4"
    rm "${FIXTURE}/$1"
}

FIX="call the namespace from deps.VFSRegistry()"

expect 0 "Go structure OK" "a clean tree passes"

plant internal/server/api/v0/files/open_file.go 1 "handler package imports os; ${FIX}" \
    "rule 4: a handler opens a path with os" <<'GO'
package v0_files

import "os"

func openFile(p string) (*os.File, error) { return os.Open(p) }
GO

plant pkg/util/fileutil/files_dir.go 1 "reads the files directory outside FILES_DIR_ALLOWED; ${FIX}" \
    "rule 5: GetFilesDir outside the allowlist" <<'GO'
package fileutil

import "github.com/autobutler-org/quark/pkg/util/storageutil"

func filesDir() (string, error) { return storageutil.GetFilesDir() }
GO

plant pkg/util/fileutil/host_path.go 1 "asks for a host path outside HOST_PATH_ALLOWED; ${FIX}" \
    "rule 6: HostPather outside the allowlist" <<'GO'
package fileutil

import "github.com/autobutler-org/quark/pkg/vfs"

func hostPath(fsys any) (string, error) { return fsys.(vfs.HostPather).HostPath("a") }
GO

plant pkg/util/fileutil/read_file.go 1 "touches the disk with os outside OS_FILE_ALLOWED; ${FIX}" \
    "rule 7: os.ReadFile under pkg/util" <<'GO'
package fileutil

import "os"

func readFile(p string) ([]byte, error) { return os.ReadFile(p) }
GO

plant pkg/util/fileutil/commented.go 0 "Go structure OK" \
    "a comment naming os.Open is not a call" <<'GO'
package fileutil

// os.Open and storageutil.GetFilesDir() in prose are fine.
GO

if [[ "${failures}" -gt 0 ]]; then
    echo ""
    echo "${failures} check-go-structure self-test case(s) failed."
    exit 1
fi
echo "check-go-structure self-test OK"
