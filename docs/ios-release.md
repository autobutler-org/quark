# iOS App Store Release

How to build and publish the Quark iOS app to the App Store from a local machine.

For *development* setup (running on your own device), see [iOS Mobile Dev Setup](./ios-dev/README.md).
This document is only about shipping to the App Store.

## Identifiers

| Thing | Value |
|---|---|
| Apple Team | `4NK7MWUA57` (Autobutler LLC) |
| Bundle ID | `org.autobutler.quark` |
| App Store listing name | Quark by AutoButler |
| Home screen name (`CFBundleDisplayName`) | Quark |

The listing name and the home screen name are deliberately different. The App Store
requires a globally unique listing name; the home screen truncates at ~12 characters.

## Prerequisites

### 1. Apple Distribution certificate

You need an **Apple Distribution** identity in your keychain — not Apple Development.
Xcode > Settings > Accounts > sign in to the team above > Manage Certificates > `+` >
Apple Distribution.

Verify:

```bash
security find-identity -v -p codesigning | grep "Apple Distribution"
```

### 2. App Store Connect API key

Create a **Team Key** with the **App Manager** role at
<https://appstoreconnect.apple.com/access/integrations/api>.

Apple serves the `.p8` file exactly once. Save it where `altool` looks for it:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
```

### 3. Secrets in `.env`

`.env` is gitignored and auto-loaded by the Makefile. See `.env.example`.

```bash
APP_STORE_CONNECT_KEY_ID=XXXXXXXXXX                          # the KEY_ID in the .p8 filename
APP_STORE_CONNECT_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxx # top of the API keys page
```

The `.p8` file itself is **not** referenced by path — `altool` finds it by key ID in
`~/.appstoreconnect/private_keys/`. Never commit it.

### Check everything at once

```bash
make check/frontend/ios/release
```

## Building and uploading

```bash
make build/frontend/ios/ipa     # clean, archive, export, verify
make publish/frontend/ios       # upload to App Store Connect
```

`build/frontend/ios/ipa` runs `flutter clean` first, then verifies the exported IPA is a
genuine release build before handing it to you. The verification exists because of a real
incident — see [Debug build shipped to
TestFlight](#debug-build-shipped-to-testflight). Set `IOS_SKIP_CLEAN=1` to skip the clean
when iterating on signing or export settings; the verification always runs.

Check an IPA by hand:

```bash
make check/frontend/ios/ipa                 # newest IPA in build/ios/ipa/
make check/frontend/ios/ipa IOS_IPA=path    # a specific one
```

The build appears in TestFlight after processing, usually 5–30 minutes.


## Continuous integration

`.github/workflows/release-ios.yml` builds and uploads from a `macos-26` runner. It runs
automatically as a job in `release.yml` on any `v*.*.*` tag push, after the GoReleaser
job succeeds, and can also be triggered by hand from the Actions tab (uncheck **upload**
to build and verify without publishing).

CI runs the same `make build/frontend/ios/ipa` target as local, so the two cannot drift.
The only difference is signing: locally Xcode signs automatically from your keychain,
while CI imports a certificate and profile into a throwaway keychain and signs manually.

### Secrets

All six are required. Add them under Settings > Secrets and variables > Actions.

| Secret | What it is |
|---|---|
| `IOS_DIST_CERT_P12_BASE64` | base64 of the Apple Distribution certificate exported as `.p12` |
| `IOS_DIST_CERT_PASSWORD` | the password you set when exporting that `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | base64 of the App Store `.mobileprovision` |
| `APP_STORE_CONNECT_KEY_ID` | API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | API issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | full contents of the `.p8`, including the BEGIN/END lines |

### Producing the certificate secret

In Keychain Access, find **Apple Distribution: Autobutler LLC**, expand it, and select
**both the certificate and its private key**. Right-click > Export 2 items > `.p12`. An
export without the private key cannot sign, and the CI script fails explicitly if that
happens.

```bash
base64 -i Certificates.p12 | pbcopy
```

### Producing the profile secret

Create an **App Store** distribution profile for `org.autobutler.quark` at
<https://developer.apple.com/account/resources/profiles>, download it, then:

```bash
base64 -i Quark_App_Store.mobileprovision | pbcopy
```

It must be a **manually managed** profile from the portal. The one Xcode generates for
you during a local archive looks identical and has the right type, but carries
`IsXcodeManaged: true`, and manual signing refuses it:

```
Provisioning profile "..." is Xcode managed, but signing settings require a
manually managed profile.
```

The CI script rejects both that and development/ad-hoc profiles up front, rather than
letting the archive discover it forty seconds in.

### Build numbers in CI

The workflow uses `github.run_number` unless you pass `build_number` explicitly. Because
App Store Connect never frees a consumed build number, a manual upload can push the real
high-water mark above the run number. If a CI upload is rejected as a duplicate, re-run
with an explicit `build_number` above the last one used.

### Expiry

Apple Distribution certificates last one year and provisioning profiles one year. Both
secrets must be regenerated before they expire, or tagged releases start failing at the
signing step. Nothing warns you in advance.

## Versioning rules

Neither number lives in `pubspec.yaml` — it has no `version:` field at all.

The **version** (`CFBundleShortVersionString`) comes from the most recent git tag, with
the leading `v` stripped: `v0.31.1` builds `0.31.1`. A build therefore cannot claim a
version that was never released, and there is no second place to remember to edit.

The **build number** (`CFBundleVersion`) is queried from App Store Connect at build time.
`scripts/ios-next-build-number.bash` asks for the highest build already uploaded for that
version and adds one.

```bash
make build/frontend/ios/ipa                       # version from the tag, build from ASC
BUILD_NAME=0.32.0 make build/frontend/ios/ipa     # override the version
IOS_BUILD_NUMBER=42 make build/frontend/ios/ipa   # skip the ASC query
```

Both need git tags present. `actions/checkout` is shallow by default and fetches none, so
the iOS jobs set `fetch-tags: true`. Without them the build fails up front rather than
silently shipping `1.0.0`, which is what Flutter defaults to when no version is supplied.

```bash
scripts/ios-next-build-number.bash                # for the current tag's version
scripts/ios-next-build-number.bash --version 1.0.0
```

Asking App Store Connect is the only way to be certain, because it is the system of
record and never frees a consumed number. Every alternative can go wrong:
`github.run_number` is a per-workflow-file counter, so a tag release and a standalone
dispatch draw from different sequences, and it does not change across a re-run — so
retrying a failed upload reuses a consumed number. A timestamp is monotonic but can never
be mixed with sequential numbering: upload `202608252313` once and every later build must
exceed it forever.

The query needs App Store Connect credentials, so builds that never upload should pass
`IOS_BUILD_NUMBER` explicitly. `build-ios` does exactly that.

This is iOS-only. Android's `versionCode` is an int32 capped at 2100000000, and Flutter
derives it by stripping non-digits from the build number. Without a `+N` in pubspec,
Android's versionCode comes from the version's own digits (`0.31.1` -> `311`).

- **Build numbers are consumed permanently.** Once App Store Connect has seen a
  `version (build)` pair, it can never be uploaded again — expiring or deleting the
  build does not free it. Always bump.
- **Released version numbers must increase.** You can upload any version to TestFlight,
  but once a version is *released* on the App Store, every later release must be higher.
- **Uploads cannot be deleted.** TestFlight builds can be *expired*; unreleased App Store
  versions can be removed from the sidebar. Neither frees the build number.

## What is already configured

Set in `ios/Runner/Info.plist`:

- `ITSAppUsesNonExemptEncryption = false` — skips the export compliance prompt on every
  upload. Correct because Quark only uses TLS and Keychain, both exempt.
- `NSAllowsLocalNetworking` (not `NSAllowsArbitraryLoads`) — the app talks to a
  self-hosted server over plain HTTP on the LAN, and nothing else.
- `NSLocalNetworkUsageDescription` — required on iOS 14+ to reach `*.local` hostnames
  and LAN IPs. Without it, connections silently fail on device.

Set in `ios/Runner.xcodeproj/project.pbxproj`:

- No hardcoded `CODE_SIGN_IDENTITY`. Automatic signing picks Apple Development for local
  builds and Apple Distribution for archives. Do not pin it back.
- `IPHONEOS_DEPLOYMENT_TARGET = 15.0`. Apple rejects uploads below 15.0 from Spring 2027.
  This costs no devices — iOS 15 runs on the same hardware as iOS 13 (iPhone 6s onward).

`ios/ExportOptions.plist` drives the export: `app-store-connect` method, automatic
signing, symbols uploaded.

## Troubleshooting

### `accessing build database ... disk I/O error`

Usually accompanied by `mkdtemp ... No such file or directory` and asset catalog errors
like `Each TDDistiller instance can be distilled only one time!`.

Something is deleting or writing DerivedData underneath the build. Two common causes:
Xcode is open on the workspace and its background build service is contending with the
CLI archive, or a `rm -rf` of DerivedData is racing the build.

Never delete DerivedData while a build is running — a half-deleted tree produces exactly
these errors. Recover with Xcode quit and nothing building:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-* \
       ~/Library/Developer/Xcode/DerivedData/Pods-*
flutter clean && flutter pub get && (cd ios && pod install)
```

If the directory reappears or `rm` reports "Directory not empty", a background Xcode
service is recreating it; that is harmless once the tree is otherwise empty.

`make build/frontend/ios/ipa` warns when Xcode is running but does not block, and it does
not touch DerivedData itself.

### `SDK version issue ... must be built with the iOS 26 SDK or later (409)`

altool rejects the upload after the archive and transfer have both succeeded:

```
Validation failed (409) SDK version issue. This app was built with the iOS 18.5 SDK.
All iOS and iPadOS apps must be built with the iOS 26 SDK or later.
```

The runner's Xcode is too old. `macos-15` images ship Xcode 16.x; `macos-26` ships
Xcode 26. Both iOS jobs run on `macos-26` for that reason, and they must stay in step: if
`build-ios` builds against an older SDK than `release-ios`, CI goes green on an artifact the
release path cannot upload.

### `MinimumOSVersion too low (90068)`

A warning, not a failure. Fixed already by the 15.0 deployment target — if it reappears,
check `IPHONEOS_DEPLOYMENT_TARGET` in the pbxproj and `platform :ios` in `ios/Podfile`
are both 15.0.

### Debug build shipped to TestFlight

Symptom: the app installs from TestFlight, then shows a black screen reading *"In iOS 14+,
debug mode Flutter apps can only be launched from Flutter tooling, IDEs with Flutter
plugins or from Xcode."*

Cause: **`FLUTTER_BUILD_MODE=debug` leaking into the build environment.** The bare
`export` near the top of the Makefile is not scoped to `.env` — GNU make applies it to
*every* variable, so `FLUTTER_BUILD_MODE ?= debug` reaches the environment of every
recipe. Flutter's `xcode_backend` reads `FLUTTER_BUILD_MODE` before falling back to
`CONFIGURATION`, so it emits debug artifacts inside an archive that `xcodebuild` is
genuinely running as `-configuration Release`. The build reports success and the IPA
uploads and installs normally. It just cannot launch.

`build/frontend/ios/ipa` pins the variable for its own recipe:

```make
build/frontend/ios/ipa: FLUTTER_BUILD_MODE := release
```

The other frontend targets pass `--$(FLUTTER_BUILD_MODE)` and so stay self-consistent;
only this target hardcodes `--release`, which is why it alone diverged. CI never hit this
— there is no `.env` on a runner, so the `export` block never activates.

To confirm the variable is clean:

```bash
make --eval='p:; @env | grep FLUTTER_BUILD_MODE' p    # should print nothing
```

How to tell them apart:

| | debug | release |
|---|---|---|
| `flutter_assets/kernel_blob.bin` | present | absent |
| `App.framework/App` | ~35 KB stub | tens of MB (AOT) |
| `Flutter.framework/Flutter` | ~39 MB (JIT) | ~9 MB |

`make check/frontend/ios/ipa` checks this, and `make build/frontend/ios/ipa` runs it
automatically. Never upload an IPA that has not been through it.

Recovery: quit Xcode and rebuild. The bad build number is gone forever — bump and
re-upload.

### `The bundle version must be higher than the previously uploaded version`

The build number was already used. Bump `version:` in `pubspec.yaml` or pass
`IOS_BUILD_NUMBER`.

## Before submitting for review

Getting a build into TestFlight is not the same as passing review. Still outstanding:

- [ ] **`PrivacyInfo.xcprivacy`** — a privacy manifest is required. Declare tracking
      status and any required-reason API use.
- [ ] **In-app account deletion** — Guideline 5.1.1(v) requires it for any app that
      supports account creation. Quark has a login flow and no deletion path.
- [ ] **A reachable demo server** — the highest rejection risk. Quark is useless without
      a backend, and a reviewer has none. Guideline 2.1 rejections follow. Stand up a
      demo instance and put the URL and credentials in App Review notes.
- [ ] App Privacy questionnaire, age rating, category, screenshots (6.9" iPhone, and 13"
      iPad while `TARGETED_DEVICE_FAMILY` is `1,2`).
- [ ] **Privacy policy URL** — required for every app. Quark does not have one yet.
