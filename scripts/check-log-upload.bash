#! /usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<'USAGE'
Usage: scripts/check-log-upload.bash

Checks that release builds compile out the networking library's diagnostic
log uploader (#3786):

  1. .goreleaser.yaml passes the ts_omit_logtail build tag, and both phone
     builds in hook/build.dart go through the argument list that passes it.
  2. With that tag, cmd/quark and cmd/tsnetbridge link the omit variant of
     tailscale.com/logtail and the disabled log-upload feature flag.
  3. Binaries built with that tag do not link logtail.(*Logger).sendLocked,
     which is the real uploader. The omit variant has no such method.

The vendor log host name is not a useful signal. A normal link already drops
it, so its absence does not mean the tag was applied. sendLocked is present
without the tag and absent with it.

Not part of `make check`: it builds two binaries. CI runs it from the
check-backend job.
USAGE
    exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

if ! command -v go >/dev/null 2>&1; then
    echo "error: go is not installed. Install Go, then run this again."
    exit 1
fi

fail() {
    echo "error: $*"
    exit 1
}

if ! grep -Eq '^[[:space:]]*-[[:space:]]*ts_omit_logtail[[:space:]]*$' .goreleaser.yaml; then
    fail ".goreleaser.yaml must pass the ts_omit_logtail build tag so release binaries compile out diagnostic log upload (#3786)."
fi

if ! grep -q "'ts_omit_logtail'" hook/build.dart; then
    fail "hook/build.dart must pass ts_omit_logtail so both phone libraries compile out diagnostic log upload (#3786)."
fi

# The definition plus the Android and iOS call sites.
go_build_args=$(grep -c '_goBuildArgs(' hook/build.dart || true)
if [[ "$go_build_args" -ne 3 ]]; then
    fail "hook/build.dart: both phone builds must call _goBuildArgs, which passes ts_omit_logtail (found ${go_build_args} mentions, want 3)."
fi

# go list prints one line per dependency. Keep the one line for this package.
go_files() {
    local pkg="$1"
    local import_path="$2"
    go list -tags ts_omit_logtail -deps -f "{{if eq .ImportPath \"${import_path}\"}}{{join .GoFiles \" \"}}{{end}}" "$pkg" \
        | grep -v '^$' \
        || true
}

has_file() {
    local files="$1"
    local want="$2"
    local f
    for f in $files; do
        if [[ "$f" == "$want" ]]; then
            return 0
        fi
    done
    return 1
}

for pkg in ./cmd/quark ./cmd/tsnetbridge; do
    logtail_files="$(go_files "$pkg" tailscale.com/logtail)"
    if ! has_file "$logtail_files" logtail_omit.go; then
        fail "${pkg}: ts_omit_logtail did not select logtail_omit.go (got: ${logtail_files:-none})."
    fi
    if has_file "$logtail_files" logtail.go; then
        fail "${pkg}: logtail.go is still compiled with ts_omit_logtail."
    fi

    feature_files="$(go_files "$pkg" tailscale.com/feature/buildfeatures)" # cspell:disable-line
    if ! has_file "$feature_files" feature_logtail_disabled.go; then
        fail "${pkg}: ts_omit_logtail did not select feature_logtail_disabled.go (got: ${feature_files:-none})."
    fi
    if has_file "$feature_files" feature_logtail_enabled.go; then
        fail "${pkg}: feature_logtail_enabled.go is still compiled with ts_omit_logtail."
    fi
done

outdir="$(mktemp -d)"
trap 'rm -rf "$outdir"' EXIT

# CGO_ENABLED=0 matches the Quark release build. The phone libraries are
# c-shared and c-archive, which need CGO, but the uploader is plain Go: the
# tag decides which files are linked, not the build mode.
echo "building cmd/quark and cmd/tsnetbridge with ts_omit_logtail"
CGO_ENABLED=0 go build -tags ts_omit_logtail -o "$outdir/quark" ./cmd/quark
CGO_ENABLED=0 go build -tags ts_omit_logtail -o "$outdir/tsnetbridge" ./cmd/tsnetbridge

for bin in quark tsnetbridge; do
    nm_out="$(go tool nm "$outdir/$bin")" || fail "go tool nm failed on ${bin}."
    if grep -F -q 'tailscale.com/logtail.(*Logger).sendLocked' <<<"$nm_out"; then
        fail "${bin}: the diagnostic log uploader is linked (logtail.(*Logger).sendLocked). ts_omit_logtail did not compile it out."
    fi
done

echo "diagnostic log upload is compiled out of the release builds"
