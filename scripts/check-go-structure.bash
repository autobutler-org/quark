#! /usr/bin/env bash

# This script enforces the Go layout conventions from AGENTS.md that a general-purpose
# linter cannot see: the interface file every package must have, version prefixes that
# disagree with their directory, handlers reaching for low-level packages, and file
# access that goes around pkg/vfs.

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: scripts/check-go-structure.bash

Checks the Go layout conventions documented in AGENTS.md:

  1. Every package under pkg/ and every router package under internal/server/api/
     has an interface file named after its own directory (albums/albums.go).
  2. No interface file declares a private func or type. The exported surface
     lives there; privates belong in types.go or helpers.go.
  3. No file carries a v<N>_ prefix that disagrees with the api version directory
     it sits in (v1_files.go inside v0/files).
  4. Handler packages under internal/server/api/ do not import the low-level
     packages that belong in pkg/util or internal/db -- os among them, so a
     handler cannot open a path it built by hand.
  5. The files directory -- storageutil.GetFilesDir, GetFilesDirForDevice,
     ConstructFilesDir, and a ManagedDevice's .FilesDir -- is read only by the
     files in FILES_DIR_ALLOWED. It is where every hand-built user path starts.
  6. vfs.HostPather, and photoutil.HostPath that wraps it, are used only by the
     files in HOST_PATH_ALLOWED: handing a path to an external tool.
  7. os file calls (os.Open, os.ReadFile, os.Remove, os.Stat, ...) and the
     filepath functions that touch the disk sit under pkg/util/ and pkg/backup/
     only in the packages and files in OS_FILE_ALLOWED, which own data outside
     the user's files.

Rules 4 to 7 keep filesystem access going through pkg/vfs; a violation's fix is
to call the namespace from deps.VFSRegistry() (see AGENTS.md, "Filesystem access
goes through pkg/vfs"). Every allowlist entry carries a comment saying why.
Comment lines and _test.go files are not checked.

Exits 0 when the tree is clean, 1 with one line per violation otherwise.
Run `make check/lint/go` to get this plus golangci-lint.
USAGE
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v go >/dev/null 2>&1; then
    echo "go is not on PATH. Install Go (see the version pinned in go.mod) and try again."
    exit 1
fi

API_ROOT="internal/server/api"

# Packages a handler must not reach for directly. Shelling out, poking at the OS, and
# opening a database driver are all somebody else's job -- pkg/util wraps the first two,
# internal/db owns the third. Deliberately short: every entry is at zero use today, so
# the list stays honest and can be tightened as the layers separate further.
FORBIDDEN_HANDLER_IMPORTS=(
    "os/exec"
    "syscall"
    "golang.org/x/sys/unix"
    "database/sql/driver"
    "modernc.org/sqlite"
    "github.com/mattn/go-sqlite3"
    # A handler opening a path goes around the device's namespace and its
    # access checks. os.Hostname and friends live in pkg/util too.
    "os"
)

# What every violation of rules 4 to 7 should do instead.
VFS_FIX="call the namespace from deps.VFSRegistry(); see AGENTS.md, Filesystem access goes through pkg/vfs"

# Rules 5 to 7 match source lines, not packages: an entry ending in / allows every
# file under that directory, any other entry allows that one file.

# 5. Who may learn where the files directory is on the host.
FILES_DIR_PATTERN='\bstorageutil\.(GetFilesDir|GetFilesDirForDevice|ConstructFilesDir)\(|\.FilesDir\b'
FILES_DIR_ALLOWED=(
    # The namespaces are built on it; this is what the rule funnels everyone into.
    "pkg/vfs/"
    # Defines the helpers and ManagedDevice, and lays out a device's data directory.
    "pkg/util/storageutil/"
    # Symlink resolution for access grants: resolveRel compares host paths (AGENTS.md).
    "pkg/util/accessutil/helpers.go"
    # Mounting a USB drive creates its files directory before any namespace exists.
    "pkg/util/deviceutil/mount.go"
    # Factory reset removes the whole files tree, namespaces and all.
    "pkg/util/authutil/authutil.go"
    # Reports where the mount put the files directory; nothing is opened.
    "internal/server/api/v0/storage/enable_usb_storage_device.go"
    # SQLite opens the vault backup on the drive, and SQLite takes a host path.
    "internal/server/api/v0/vault/import_vault_backup.go"
)

# 6. Who may turn a namespace path into a host path.
HOST_PATH_PATTERN='\bHostPather\b|\bHostPath\('
HOST_PATH_ALLOWED=(
    # Declares HostPather and implements it.
    "pkg/vfs/"
    # photoutil.HostPath: the one wrapper the RAW converter and exiftool go through.
    "pkg/util/photoutil/device.go"
    # A RAW photo's hash comes from the converter, which takes a host path.
    "pkg/util/photoutil/hashes.go"
    # Thumbnails of RAW photos and video frames come from dcraw and ffmpeg.
    "pkg/util/thumbnailutil/generate.go"
    # A RAW download converted to JPEG goes through dcraw.
    "pkg/util/fileutil/download.go"
    # The vault export is written by SQLite, which takes a host directory.
    "pkg/backup/snapshot.go"
)

# 7. Who under pkg/util/ and pkg/backup/ may touch the disk with os directly.
OS_FILE_ROOTS=("pkg/util" "pkg/backup")
OS_FILE_PATTERN='\bos\.(Open|OpenFile|OpenInRoot|OpenRoot|Create|CreateTemp|ReadFile|WriteFile|ReadDir|Remove|RemoveAll|Rename|Mkdir|MkdirAll|MkdirTemp|Stat|Lstat|Symlink|Readlink|Link|Chmod|Chown|Lchown|Chtimes|Truncate|DirFS|CopyFS)\(|\bfilepath\.(Walk|WalkDir|Glob|EvalSymlinks)\(|\bioutil\.'
OS_FILE_ALLOWED=(
    # Devices, mounts, partitions, the data directory, durable writes, the tmp dir,
    # and the byte accounting behind the storage page.
    "pkg/util/storageutil/"
    # Mounting and unmounting USB drives.
    "pkg/util/deviceutil/"
    # System configuration: settings, the hostname helper, remote access, updates,
    # ssh keys, repair, provisioning, TLS certificates, apt holds and memory tuning.
    "pkg/util/settingsutil/"
    "pkg/util/hostnameutil/"
    "pkg/util/remoteutil/"
    "pkg/util/updateutil/"
    "pkg/util/sshutil/"
    "pkg/util/repairutil/"
    "pkg/util/provisionutil/"
    "pkg/util/tlsutil/"
    "pkg/util/aptutil/"
    "pkg/util/memutil/"
    # Avatars live in the data directory, not the user's files.
    "pkg/util/avatarutil/"
    # Per-user settings and the account request history are in the database;
    # each imports, then retires, the files an older Quark kept in the data directory.
    "pkg/util/usersettingsutil/"
    "pkg/util/requestlogutil/"
    # The thumbnail cache, and the temp files dcraw and ffmpeg write into.
    "pkg/util/thumbnailutil/"
    # Upload and transcode staging, outside the files tree until committed.
    "pkg/util/uploadutil/"
    "pkg/util/transcodeutil/"
    # RAW conversion temp files, and decoding the host path HostPath handed out.
    "pkg/util/photoutil/"
    # Probe and Keyframe open a video by the host path the thumbnail generator holds.
    "pkg/util/videoutil/"
    # Symlink resolution for access grants (AGENTS.md).
    "pkg/util/accessutil/helpers.go"
    # Factory reset: DeleteAccount removes the data directory and stale mount points.
    "pkg/util/authutil/"
    # The vault and chat exports and imports are SQLite files outside the user's files.
    "pkg/backup/vault_export.go"
    "pkg/backup/vault_import.go"
    "pkg/backup/chat_export.go"
    "pkg/backup/chat_import.go"
    # When the last snapshot backup completed is in the database; this imports,
    # then retires, the file an older Quark kept in the data directory.
    "pkg/backup/last_snapshot.go"
)

violations=0

fail() {
    echo "$1"
    violations=$((violations + 1))
}

# allowed FILE ENTRY... reports whether FILE is covered by one of the allowlist
# entries: equal to it, or beneath it when the entry ends in /.
allowed() {
    local file="$1" entry
    shift
    for entry in "$@"; do
        if [[ "${file}" == "${entry}" || ("${entry}" == */ && "${file}" == "${entry}"*) ]]; then
            return 0
        fi
    done
    return 1
}

# check_lines RULE PATTERN ROOTS... -- ALLOWED... fails every non-test, non-comment
# line under ROOTS that matches PATTERN, unless its file is allowed.
check_lines() {
    local rule="$1" pattern="$2" roots=() hit file
    shift 2
    while [[ "$1" != "--" ]]; do
        roots+=("$1")
        shift
    done
    shift
    while IFS= read -r hit; do
        [[ -z "${hit}" ]] && continue
        file="${hit%%:*}"
        allowed "${file}" "$@" && continue
        fail "${hit}: ${rule}; ${VFS_FIX}"
    done < <(grep -rnE --include='*.go' "${pattern}" "${roots[@]}" 2>/dev/null |
        grep -v '_test\.go:' |
        grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' |
        sort || true)
}

# Collected up front rather than piped straight into the loops: a `go list` that fails
# on the far side of a pipe would leave the loop with nothing to read, and the script
# would report a clean tree for code that does not even compile.
if ! PACKAGE_DIRS="$(go list -f '{{.Dir}}' ./pkg/... "./${API_ROOT}/...")"; then
    echo "go list failed -- the tree does not build, so its structure cannot be checked."
    exit 1
fi
if ! API_IMPORTS="$(go list -f '{{.ImportPath}} {{join .Imports " "}}' "./${API_ROOT}/...")"; then
    echo "go list failed -- the tree does not build, so its structure cannot be checked."
    exit 1
fi

# 1. Every directory holding Go code needs the interface file named after itself.
#    `go list` is the source of truth for "is this a package" -- a directory of only
#    _test.go files or of only subdirectories (pkg/util) is not one.
#
# 2. And that file is the package's public face, so nothing private may sit in it.
#    grep rather than a parser: a private top-level declaration always opens its line
#    with `func x` or `type x`, an exported one with a capital, and a method reads
#    `func (r *router)`. Consts and vars are deliberately not checked -- a private
#    tuning value next to the exported thing it tunes is not the sprawl this catches,
#    and flagging every one of them would drown the signal.
while read -r dir; do
    pkg="$(basename "${dir}")"
    if [[ ! -f "${dir}/${pkg}.go" ]]; then
        fail "${dir}: missing interface file ${pkg}.go (see AGENTS.md, API package layout)"
        continue
    fi
    while read -r decl; do
        [[ -z "${decl}" ]] && continue
        fail "${dir}/${pkg}.go: private '${decl}' in the interface file; move it to types.go or helpers.go (see AGENTS.md, API package layout)"
    done < <(grep -oE '^(func|type) [a-z][A-Za-z0-9_]*' "${dir}/${pkg}.go" || true)
done < <(echo "${PACKAGE_DIRS}" | sed "s|^${REPO_ROOT}/||" | sort)

# 3. A v<N>_ filename prefix that disagrees with the version directory it lives in.
#    v1_files.go inside v0/files is a rename someone started and did not finish.
while read -r file; do
    prefix="$(basename "${file}" | sed -E 's/^(v[0-9]+)_.*/\1/')"
    version="$(echo "${file}" | sed -E "s|^${API_ROOT}/(v[0-9]+)/.*|\1|")"
    if [[ "${prefix}" != "${version}" ]]; then
        fail "${file}: ${prefix}_ prefix disagrees with its ${version}/ directory"
    fi
done < <(find "${API_ROOT}" -name 'v[0-9]*_*.go' | sort)

# 4. Handlers route and validate; they do not do the work themselves. Enforced as an
#    import deny-list, because "business logic" is not something grep can recognize.
while read -r pkg_imports; do
    pkg="${pkg_imports%% *}"
    for forbidden in "${FORBIDDEN_HANDLER_IMPORTS[@]}"; do
        if [[ " ${pkg_imports#* } " == *" ${forbidden} "* ]]; then
            fix="move that work into pkg/util or internal/db"
            [[ "${forbidden}" == "os" ]] && fix="${VFS_FIX}"
            fail "${pkg}: handler package imports ${forbidden}; ${fix}"
        fi
    done
done < <(echo "${API_IMPORTS}")

# 5 to 7. File access goes through pkg/vfs. The compiler already keeps the storage
# service's file operations out of reach; what it cannot see is a path built by hand
# and handed to os. So these follow the three ways such a path starts: the files
# directory, a namespace's host path, and os itself.
GO_ROOTS=()
for root in cmd internal pkg; do
    [[ -d "${root}" ]] && GO_ROOTS+=("${root}")
done
check_lines "reads the files directory outside FILES_DIR_ALLOWED" "${FILES_DIR_PATTERN}" \
    "${GO_ROOTS[@]}" -- "${FILES_DIR_ALLOWED[@]}"
check_lines "asks for a host path outside HOST_PATH_ALLOWED" "${HOST_PATH_PATTERN}" \
    "${GO_ROOTS[@]}" -- "${HOST_PATH_ALLOWED[@]}"
OS_ROOTS=()
for root in "${OS_FILE_ROOTS[@]}"; do
    [[ -d "${root}" ]] && OS_ROOTS+=("${root}")
done
if [[ "${#OS_ROOTS[@]}" -gt 0 ]]; then
    check_lines "touches the disk with os outside OS_FILE_ALLOWED" "${OS_FILE_PATTERN}" \
        "${OS_ROOTS[@]}" -- "${OS_FILE_ALLOWED[@]}"
fi

if [[ "${violations}" -gt 0 ]]; then
    echo ""
    echo "${violations} Go structure violation(s). The conventions are documented in AGENTS.md."
    exit 1
fi

echo "Go structure OK"
