#! /usr/bin/env bash

# Prepares a macOS CI runner to produce a signed App Store build:
#   1. imports the Apple Distribution certificate into a throwaway keychain
#   2. installs the App Store provisioning profiles: the app's and the AutoFill
#      extension's (ios/CredentialProvider, #3598)
#   3. writes an ExportOptions plist wired for manual signing
#
# Reads its inputs from the environment so nothing sensitive lands in argv or
# in the shell history of a runner log.

set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: scripts/ios-ci-signing.bash [--out PATH]

Prepares iOS App Store code signing on a CI runner. macOS only.

Options:
  --out PATH   Where to write the generated ExportOptions plist.
               Default: ios/ExportOptions.ci.plist
  -h, --help   Show this help.

Required environment variables:
  IOS_DIST_CERT_P12_BASE64        base64 of the Apple Distribution .p12
  IOS_DIST_CERT_PASSWORD          password protecting that .p12
  IOS_PROVISIONING_PROFILE_BASE64 base64 of the app's App Store .mobileprovision
  IOS_AUTOFILL_PROVISIONING_PROFILE_BASE64
                                  base64 of the AutoFill extension's App Store
                                  .mobileprovision (org.autobutler.quark.CredentialProvider)

To produce the base64 values locally:
  base64 -i Certificates.p12 | pbcopy
  base64 -i Quark_App_Store.mobileprovision | pbcopy
  base64 -i Quark_AutoFill_App_Store.mobileprovision | pbcopy

See docs/ios-release.md for how to obtain the certificate and profile.
USAGE
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="ios/ExportOptions.ci.plist"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) OUT="${2:?--out needs a path}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Error: unknown argument '$1'"; echo; usage; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: iOS code signing requires macOS (found $(uname -s))."
    echo "  Fix: run this job on a macos-* runner."
    exit 1
fi

missing=0
for var in IOS_DIST_CERT_P12_BASE64 IOS_DIST_CERT_PASSWORD IOS_PROVISIONING_PROFILE_BASE64 \
    IOS_AUTOFILL_PROVISIONING_PROFILE_BASE64; do
    if [[ -z "${!var:-}" ]]; then
        echo "Error: ${var} is not set."
        missing=1
    fi
done
if [[ "${missing}" -ne 0 ]]; then
    echo
    echo "These come from GitHub Actions secrets. Run with --help for how to generate them,"
    echo "or see docs/ios-release.md."
    exit 1
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

CERT_PATH="${WORK_DIR}/dist.p12"
PROFILE_PATH="${WORK_DIR}/profile.mobileprovision"
AUTOFILL_PROFILE_PATH="${WORK_DIR}/autofill.mobileprovision"
decode_secret() {
    local var_name="$1" out="$2" what="$3"
    if ! printf '%s' "${!var_name}" | base64 --decode > "${out}" 2>/dev/null; then
        echo "Error: ${var_name} is not valid base64."
        echo "  Set it from the file's base64, not the file itself:"
        echo "    base64 -i <file> | gh secret set ${var_name} --repo <owner>/<repo>"
        exit 1
    fi
    if [[ ! -s "${out}" ]]; then
        echo "Error: ${var_name} decoded to an empty ${what}."
        exit 1
    fi
}
decode_secret IOS_DIST_CERT_P12_BASE64 "${CERT_PATH}" "certificate"
decode_secret IOS_PROVISIONING_PROFILE_BASE64 "${PROFILE_PATH}" "profile"
decode_secret IOS_AUTOFILL_PROVISIONING_PROFILE_BASE64 "${AUTOFILL_PROFILE_PATH}" "profile"

# A dedicated keychain keeps the runner's login keychain untouched and lets the
# job leave no credentials behind. The password is ephemeral and never leaves
# this process.
#
# It must NOT live in WORK_DIR: that is removed by the EXIT trap, which would delete
# the keychain the moment this script finishes and leave the search list pointing at a
# file that no longer exists. Later build steps would then fail with "no Apple
# Distribution identity" despite this script reporting success.
KEYCHAIN_DIR="${HOME}/Library/Keychains"
mkdir -p "${KEYCHAIN_DIR}"
KEYCHAIN="${KEYCHAIN_DIR}/quark-signing.keychain-db"
# Recreate from scratch so a rerun on a warm runner cannot inherit stale contents.
security delete-keychain "${KEYCHAIN}" 2>/dev/null || true
KEYCHAIN_PASSWORD="$(uuidgen)"

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security set-keychain-settings -lut 21600 "${KEYCHAIN}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}"
security import "${CERT_PATH}" \
    -k "${KEYCHAIN}" \
    -P "${IOS_DIST_CERT_PASSWORD}" \
    -T /usr/bin/codesign \
    -T /usr/bin/security \
    -f pkcs12 \
    -A >/dev/null
# Without this, codesign blocks on a GUI prompt that no runner can answer.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN}" >/dev/null
security list-keychains -d user -s "${KEYCHAIN}" $(security list-keychains -d user | tr -d '"')

if ! security find-identity -v -p codesigning "${KEYCHAIN}" | grep -q "Apple Distribution"; then
    echo "Error: no 'Apple Distribution' identity found after importing the .p12."
    echo "  The certificate is probably an Apple Development cert, or the export"
    echo "  omitted its private key. Re-export from Keychain Access selecting BOTH"
    echo "  the certificate and its private key."
    exit 1
fi

# Check again without naming the keychain. Everything downstream -- xcodebuild,
# codesign, check/frontend/ios/release -- resolves identities through the default
# search list, so verifying only the keychain we just built would miss a search-list
# problem and fail later with a far less obvious message.
if ! security find-identity -v -p codesigning | grep -q "Apple Distribution"; then
    echo "Error: the identity imported but is not visible through the default keychain"
    echo "  search list, so codesign and xcodebuild will not find it."
    echo "  Current search list:"
    security list-keychains -d user | sed 's/^/    /'
    exit 1
fi

# Reads a profile's own metadata rather than hardcoding a name that Apple may
# regenerate, checks it is a manually managed App Store profile, and installs it.
# Sets PROFILE_NAME, PROFILE_UUID, TEAM_ID and BUNDLE_ID.
install_profile() {
    local var_name="$1" path="$2"
    # The profile is a CMS-signed plist.
    local plist="${WORK_DIR}/${var_name}.plist"
    # Do not silence this: under `set -e` a suppressed failure here exits the script with
    # no output at all, which is the least debuggable thing it can do.
    if ! security cms -D -i "${path}" > "${plist}" 2>"${WORK_DIR}/cms.err"; then
        echo "Error: ${var_name} did not decode to a valid"
        echo "  .mobileprovision file. 'security cms' said:"
        sed 's/^/    /' "${WORK_DIR}/cms.err"
        echo
        echo "  Decoded $(wc -c < "${path}" | tr -d ' ') bytes; first 16 bytes were:"
        echo "    $(head -c 16 "${path}" | xxd -p 2>/dev/null || true)"
        echo "  A real profile begins with an ASN.1 SEQUENCE (hex 3082...)."
        echo
        echo "  Regenerate the secret with:"
        echo "    base64 -i <file>.mobileprovision \\"
        echo "      | gh secret set ${var_name} --repo <owner>/<repo>"
        exit 1
    fi

    PROFILE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :Name' "${plist}")"
    PROFILE_UUID="$(/usr/libexec/PlistBuddy -c 'Print :UUID' "${plist}")"
    TEAM_ID="$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "${plist}")"
    local app_id
    app_id="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "${plist}")"
    BUNDLE_ID="${app_id#"${TEAM_ID}."}"

    if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "${plist}" >/dev/null 2>&1; then
        echo "Error: '${PROFILE_NAME}' is a development or ad-hoc profile (it lists devices)."
        echo "  App Store distribution needs a profile of type 'App Store Connect'."
        echo "  Create one at https://developer.apple.com/account/resources/profiles"
        exit 1
    fi

    # Xcode-managed profiles are the ones automatic signing generates for you. Manual
    # signing refuses them outright -- "is Xcode managed, but signing settings require a
    # manually managed profile" -- and the archive only discovers that ~40s in. Catch it now.
    if [[ "$(/usr/libexec/PlistBuddy -c 'Print :IsXcodeManaged' "${plist}" 2>/dev/null)" == "true" ]]; then
        echo "Error: '${PROFILE_NAME}' is an Xcode-managed profile."
        echo "  CI signs manually, and Xcode refuses to use a managed profile that way."
        echo "  Reusing the one Xcode created locally will not work, however convenient."
        echo
        echo "  Fix: create a manually managed profile at"
        echo "       https://developer.apple.com/account/resources/profiles"
        echo "       Type 'App Store Connect', App ID '${BUNDLE_ID}', your Apple Distribution"
        echo "       certificate. Then:"
        echo "         base64 -i <downloaded>.mobileprovision \\"
        echo "           | gh secret set ${var_name} --repo <owner>/<repo>"
        exit 1
    fi

    # Xcode 16 moved the profile directory. xcodebuild still reads the legacy path, but
    # which one wins depends on the toolchain version on the runner, so install to both.
    local dir
    for dir in \
        "${HOME}/Library/MobileDevice/Provisioning Profiles" \
        "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
        mkdir -p "${dir}"
        cp "${path}" "${dir}/${PROFILE_UUID}.mobileprovision"
    done
}

install_profile IOS_AUTOFILL_PROVISIONING_PROFILE_BASE64 "${AUTOFILL_PROFILE_PATH}"
AUTOFILL_PROFILE_NAME="${PROFILE_NAME}"
AUTOFILL_PROFILE_UUID="${PROFILE_UUID}"
AUTOFILL_TEAM_ID="${TEAM_ID}"
AUTOFILL_BUNDLE_ID="${BUNDLE_ID}"
install_profile IOS_PROVISIONING_PROFILE_BASE64 "${PROFILE_PATH}"

# The extension's App ID sits under the app's, and both sign with one team's certificate.
if [[ "${AUTOFILL_BUNDLE_ID}" != "${BUNDLE_ID}.CredentialProvider" || "${AUTOFILL_TEAM_ID}" != "${TEAM_ID}" ]]; then
    echo "Error: IOS_AUTOFILL_PROVISIONING_PROFILE_BASE64 is for '${AUTOFILL_BUNDLE_ID}'"
    echo "  (team ${AUTOFILL_TEAM_ID}), expected '${BUNDLE_ID}.CredentialProvider' (team ${TEAM_ID})."
    echo "  The two secrets are probably swapped, or the extension's profile is for another App ID."
    exit 1
fi

# `flutter build ipa` archives using the project's own signing settings, and the Runner
# target specifies none -- so Xcode falls back to automatic signing, which needs an Apple
# ID in Xcode > Settings > Accounts and fails on a runner with "No Accounts: Add a new
# account in Accounts settings."
#
# The Runner target defines no CODE_SIGN_STYLE or CODE_SIGN_IDENTITY of its own and uses
# Flutter/Release.xcconfig as the base configuration for its Release build, so settings
# appended here reach the archive. Later assignments win in an xcconfig, so this must go
# at the end, after the CocoaPods include.
RELEASE_XCCONFIG="${REPO_ROOT}/ios/Flutter/Release.xcconfig"
MARKER="// --- quark ci signing (generated; not for commit) ---"

if [[ ! -f "${RELEASE_XCCONFIG}" ]]; then
    echo "Error: ${RELEASE_XCCONFIG} not found."
    exit 1
fi
# Idempotent: drop any block a previous run left behind. Truncating by line number
# avoids sed delimiter trouble -- the marker contains '/' characters.
if grep -qF "${MARKER}" "${RELEASE_XCCONFIG}"; then
    MARKER_LINE="$(grep -nF "${MARKER}" "${RELEASE_XCCONFIG}" | head -1 | cut -d: -f1)"
    head -n "$((MARKER_LINE - 1))" "${RELEASE_XCCONFIG}" > "${RELEASE_XCCONFIG}.tmp"
    command mv -f "${RELEASE_XCCONFIG}.tmp" "${RELEASE_XCCONFIG}"
fi
cat >> "${RELEASE_XCCONFIG}" <<XCCONFIG
${MARKER}
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Distribution
PROVISIONING_PROFILE_SPECIFIER = ${PROFILE_NAME}
DEVELOPMENT_TEAM = ${TEAM_ID}
XCCONFIG

# The extension does not build on Flutter's Release.xcconfig, so the block above never
# reaches it. Its own xcconfig includes this file when it exists (.gitignore keeps it out
# of commits).
AUTOFILL_XCCONFIG="${REPO_ROOT}/ios/CredentialProvider/Signing.ci.xcconfig"
cat > "${AUTOFILL_XCCONFIG}" <<XCCONFIG
${MARKER}
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Distribution
PROVISIONING_PROFILE_SPECIFIER = ${AUTOFILL_PROFILE_NAME}
DEVELOPMENT_TEAM = ${TEAM_ID}
XCCONFIG

cat > "${OUT}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!-- Generated by scripts/ios-ci-signing.bash. Do not commit. -->
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Apple Distribution</string>
	<key>provisioningProfiles</key>
	<dict>
		<key>${BUNDLE_ID}</key>
		<string>${PROFILE_NAME}</string>
		<key>${AUTOFILL_BUNDLE_ID}</key>
		<string>${AUTOFILL_PROFILE_NAME}</string>
	</dict>
	<key>destination</key>
	<string>export</string>
	<key>uploadSymbols</key>
	<true/>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

plutil -lint "${OUT}" >/dev/null

echo "Signing ready."
echo "  Team:    ${TEAM_ID}"
echo "  Bundle:  ${BUNDLE_ID}"
echo "  Profile: ${PROFILE_NAME} (${PROFILE_UUID})"
echo "  AutoFill: ${AUTOFILL_BUNDLE_ID}, ${AUTOFILL_PROFILE_NAME} (${AUTOFILL_PROFILE_UUID})"
echo "  Export:  ${OUT}"
echo "  Keychain: ${KEYCHAIN}"
echo "  Archive signing pinned to Manual in ${RELEASE_XCCONFIG#"${REPO_ROOT}/"}"
echo "    and ${AUTOFILL_XCCONFIG#"${REPO_ROOT}/"}"
