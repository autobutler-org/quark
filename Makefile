SHELL := bash
.SHELLFLAGS = -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:

# .ONESHELL needs GNU Make 3.82+. macOS ships 3.81, where it is silently ignored and
# every recipe line runs in its own shell -- multi-line `if` blocks then die with
# "syntax error: unexpected end of file", which points nowhere near the real problem.
MIN_MAKE := 3.82
ifneq ($(firstword $(sort $(MAKE_VERSION) $(MIN_MAKE))),$(MIN_MAKE))
$(error GNU Make $(MAKE_VERSION) is too old; this Makefile needs $(MIN_MAKE)+. \
On macOS run `brew install make` and use `gmake`, or put \
"$$(brew --prefix)/opt/make/libexec/gnubin" first on PATH.)
endif

# The bare `export` below exports every variable, so make expands all of them into
# each recipe's environment. A `?=` or `=` variable holding a $(shell ...) is
# recursively expanded and re-runs its subprocess every single time -- which cost
# ~50 seconds per invocation before the := conversions below. Keep shell-backed
# variables simply-expanded, and use $(or ...) so an override still wins. See #1726.
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Keep git's per-invocation environment out of recipes. When make runs from a git
# hook (see `make setup/hooks`), git exports GIT_DIR and friends pointing at this
# repository. Flutter reads its own version with git, so it then inspects the wrong
# checkout, reports 0.0.0-unknown, and every pub resolution fails against the
# `flutter:` version pinned in pubspec.yaml.
unexport GIT_DIR
unexport GIT_INDEX_FILE
unexport GIT_WORK_TREE
unexport GIT_PREFIX

GO := $(shell which go)
PROBE_VERSION := v0.14.0
AIR := $(shell which air)
# Only ask Go for its defaults when Go is actually installed. On a macOS CI runner
# without it, $(GO) is empty and the shell call becomes `env GOOS`, which floods the
# log with "env: GOOS: No such file or directory" on every recipe.
ifneq ($(GO),)
export GOOS := $(or $(GOOS),$(shell $(GO) env GOOS))
export GOARCH := $(or $(GOARCH),$(shell $(GO) env GOARCH))
endif
export GOPROXY ?= https://proxy.golang.org,direct

ENTRYPOINT := ./cmd/quark
EXE := ./build/quark

# The app version comes from the most recent git tag, so a build can never claim a
# version that was never released. pubspec.yaml deliberately has no `version:` field --
# it was a second place to edit and drifted from the tags it was meant to track.
# Override with BUILD_NAME=X.Y.Z.
BUILD_NAME := $(or $(BUILD_NAME),$(shell git describe --tags --abbrev=0 2>/dev/null | sed -E 's/^v//'))

# Dev runs get no tag: `flutter run` stamps no --build-name, on purpose -- a dirty
# working tree must not report itself as a released version. The commit identifies it
# instead, passed as a Dart compile-time constant so it reaches web the same as mobile
# (version.json is a release-build artifact; --build-number is an integer on Android).
# Seven characters to match what the Quark's own commit is shortened to in Settings.
GIT_SHA := $(or $(GIT_SHA),$(shell git rev-parse --short=7 HEAD 2>/dev/null))
FLUTTER_RUN_DEFINES := $(if $(GIT_SHA),--dart-define=GIT_SHA=$(GIT_SHA),)

# AS_ROOT=1 runs the backend targets under sudo. Needed for USB device mounting
# on Linux, and for binding the privileged :443 port that the secure targets use.
# The env assignment is placed after sudo (via `env`) rather than before it, so
# it survives sudo's environment scrubbing without depending on `sudo -E` being
# permitted by sudoers.
ifeq ($(AS_ROOT),1)
SUDO := sudo
else
SUDO :=
endif

# Auto-detect Chromium-based browser for Flutter web if CHROME_EXECUTABLE
# is not already set.  Brave is checked first because users who removed
# Chrome in favour of Brave still need a Chromium engine for Flutter.
ifndef CHROME_EXECUTABLE
  ifneq (,$(shell test -f '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser' && echo found))
    export CHROME_EXECUTABLE := /Applications/Brave Browser.app/Contents/MacOS/Brave Browser
  endif
endif

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)
FLUTTER_VERSION := $(shell grep -Eo 'flutter: (.+)' pubspec.yaml | sed -E 's/^flutter: (.+)$$/\1/')
GO_MOD_VERSION := $(shell awk '/^go /{print $$2; exit}' go.mod)
export GOTOOLCHAIN=go$(GO_MOD_VERSION)

.PHONY: clean
clean: clean/go clean/flutter clean/docker ## Clean all build and test artifacts

.PHONY: clean/go
clean/go: ## Clean Go build artifacts
	rm -rf ./build

.PHONY: clean/flutter
clean/flutter: ## Clean flutter project
	flutter clean

# Deliberately not dependent on check/docker, and silent about every failure: `clean` is run
# casually and on machines with no Docker at all, so a missing daemon or a container that was
# never created is nothing to report. Leaves $(DOCKER_VOLUME) alone -- that is the user's data,
# not a build artifact.
.PHONY: clean/docker
clean/docker: ## Remove the $(DOCKER_CONTAINER) container (keeps the $(DOCKER_VOLUME) volume)
	docker rm -f $(DOCKER_CONTAINER) >/dev/null 2>&1 || true

.PHONY: setup
setup: setup/gotools setup/golangci-lint setup/probe setup/air setup/sqlc setup/swag setup/flutter setup/skills setup/hooks ## Setup development environment

.PHONY: setup/skills
setup/skills: ## Install the pub package skills bundled with our packages
	# Reads every workspace dependency's `skills/` directory and writes the
	# ones it finds into .claude/skills (Claude Code) and .agents/skills
	# (everything else). Both are gitignored, so this leaves the tree clean.
	dart run skills@ get --all

.PHONY: setup/wrk
setup/wrk: ## Install wrk load-testing CLI
ifeq ($(UNAME_S),Linux)
	sudo apt-get update -y
	sudo apt-get install -y wrk
else ifeq ($(UNAME_S),Darwin)
	brew install wrk
else
	$(error "Unsupported OS: $(UNAME_S)")
endif

.PHONY: setup/air
setup/air: ## Install air tool
	$(GO) install github.com/air-verse/air@latest

.PHONY: setup/cocoapods
setup/cocoapods: ## Setup CocoaPods for iOS development
ifeq ($(UNAME_S),Darwin)
	brew install ruby
	$$(brew --prefix)/opt/ruby/bin/gem install cocoapods
	echo "Make sure to put $$(gem env gemdir)/bin in your PATH to use the installed cocoapods"
else
	$(error "CocoaPods setup is only supported on macOS")
endif

.PHONY: setup/flutter
setup/flutter: ## Install Flutter tools
	if [ -d "${HOME}/flutter" ]; then
		echo "Flutter already installed at ${HOME}/flutter"
		exit 0
	fi
	if [ -z "$(FLUTTER_VERSION)" ]; then
		echo "Error: Could not determine Flutter version from pubspec.yaml"
		exit 1
	fi
	echo "Installing Flutter version $(FLUTTER_VERSION)"
ifeq ($(UNAME_S),Linux)
	sudo apt-get update -y
	sudo apt-get install -y \
		curl \
		git \
		libglu1-mesa \
		unzip \
		xz-utils \
		zip
ifeq ($(UNAME_M),aarch64)
	# The official Flutter Linux tarball ships with an x86_64 Dart SDK only.
	# On ARM64 (e.g. Raspberry Pi), we download the tarball for Flutter's tooling
	# and directory structure, then swap in the native ARM64 Dart SDK from apt.
	curl --fail -L \
		"https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$(FLUTTER_VERSION)-stable.tar.xz" \
		-o /tmp/flutter.tar.xz
	tar -xf /tmp/flutter.tar.xz -C "${HOME}"
	rm -f /tmp/flutter.tar.xz
	# Install ARM64 Dart SDK
	curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/dart.gpg
	echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=arm64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | sudo tee /etc/apt/sources.list.d/dart_stable.list
	sudo apt-get update -y
	sudo apt-get install -y dart
	# Replace the x86_64 Dart SDK bundled with Flutter with the native ARM64 one
	rsync -a /usr/lib/dart/ "${HOME}/flutter/bin/cache/dart-sdk/"
	# Remove the pre-compiled x86_64 flutter_tools snapshot so Flutter rebuilds it
	# with the ARM64 Dart SDK on first run
	rm -f "${HOME}/flutter/bin/cache/flutter_tools.snapshot" \
		  "${HOME}/flutter/bin/cache/flutter_tools.stamp"
else
	curl --fail -L \
		"https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$(FLUTTER_VERSION)-stable.tar.xz" | \
			tar \
				-xJf - \
				-C "${HOME}"
endif
else ifeq ($(UNAME_S),Darwin)
	rm -f flutter.zip
	set -v
	curl --fail -L \
		"https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_$(FLUTTER_VERSION)-stable.zip" \
		-o flutter.zip
	unzip flutter.zip -d "${HOME}"
	rm -f flutter.zip

	echo "Since on Mac, setting up iOS development environment..."
	$(MAKE) setup/ios
else
	$(error "Unsupported OS: $(UNAME_S)")
endif

.PHONY: setup/gotools
setup/gotools: ## Install go tools
	$(GO) install golang.org/x/tools/gopls@latest
	$(GO) install github.com/cweill/gotests/gotests@v1.6.0
	$(GO) install github.com/josharian/impl@v1.4.0
	$(GO) install github.com/haya14busa/goplay/cmd/goplay@v1.0.0
	$(GO) install github.com/go-delve/delve/cmd/dlv@latest
	$(GO) install golang.org/x/vuln/cmd/govulncheck@latest
	# staticcheck is not installed on its own -- golangci-lint runs it as one of its
	# linters, and two copies at different versions disagree about what is a warning.

.PHONY: setup/ios
setup/ios: setup/cocoapods ## Setup iOS development environment
ifeq ($(UNAME_S),Darwin)
	sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
	sudo xcodebuild -license
	xcodebuild -downloadPlatform iOS
	sudo softwareupdate --install-rosetta --agree-to-license
else
	$(error "iOS development environment setup is only supported on macOS")
endif

.PHONY: setup/sqlc
setup/sqlc: ## Install sqlc tool
	$(GO) install github.com/sqlc-dev/sqlc/cmd/sqlc@v1.30.0

.PHONY: setup/golangci-lint
setup/golangci-lint: ## Install golangci-lint
	$(GO) install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.6.2

.PHONY: setup/probe
setup/probe: ## Install the Flutter Probe e2e CLI and its MCP server (probe, probe-mcp)
	$(GO) install github.com/alphawavesystems/flutter-probe/cmd/probe@$(PROBE_VERSION)
	$(GO) install github.com/alphawavesystems/flutter-probe/cmd/probe-mcp@$(PROBE_VERSION)

.PHONY: setup/swag
setup/swag: ## Install swag tool
	$(GO) install github.com/swaggo/swag/cmd/swag@latest

.PHONY: setup/hooks
setup/hooks: ## Install git hooks
	ln -sf "$(PWD)/git/hooks/pre-commit" .git/hooks/pre-commit
	echo "✅ Git hooks installed"

.PHONY: setup/node
setup/node: ## Install and use the Node.js version from .nvmrc via nvm
	if [ ! -s "$$HOME/.nvm/nvm.sh" ]; then
		echo "nvm is not installed. See https://github.com/nvm-sh/nvm#installing-and-updating"
		exit 1
	fi
	. "$$HOME/.nvm/nvm.sh" && nvm install && nvm use

##@ Development

.PHONY: build
build: ## Build web frontend and backend
	$(MAKE) build/frontend/web
	$(MAKE) build/backend

# Only the commit, never Semver: NOSEMVER is what makes CompareVersions return 2,
# which is the guard that stops autoupdate installing over a dev binary. Stamping a
# version here would arm it (see internal/server/autoupdate.go).
#
# Every way of starting the backend needs this, `go run` most of all: it records no
# vcs.revision at all, so a `serve/backend` process has nothing to fall back on and
# reports NOCOMMIT without it.
GO_LDFLAGS := $(if $(GIT_SHA),-ldflags "-X github.com/autobutler-org/quark/pkg/util/versionutil.GitCommit=$(GIT_SHA)",)

.PHONY: build/backend
build/backend: internal/server/public/stub.txt generate/backend ## Build backend
	mkdir -p ./build
	$(GO) build $(GO_LDFLAGS) -o $(EXE) $(ENTRYPOINT)

internal/server/public/stub.txt: ## Ensure public directory exists for embedding
	mkdir -p ./internal/server/public
	touch ./internal/server/public/stub.txt

.PHONY: build/frontend
build/frontend: ## Build mobile app
ifeq ($(UNAME_S),Linux)
	make build/frontend/android
else ifeq ($(UNAME_S),Darwin)
	make build/frontend/ios
else
	$(error "Unsupported OS: $(UNAME_S)")
endif

FLUTTER_BUILD_MODE ?= debug

.PHONY: build/frontend/android
build/frontend/android: generate/frontend/sbom ## Build Android app
	flutter build apk --$(FLUTTER_BUILD_MODE) $(if $(BUILD_NAME),--build-name=$(BUILD_NAME),)

.PHONY: build/frontend/ios
build/frontend/ios: generate/frontend/sbom ## Build iOS app
	flutter build ios --$(FLUTTER_BUILD_MODE) --no-codesign \
		$(if $(BUILD_NAME),--build-name=$(BUILD_NAME),)

# App Store Connect distribution. A build number must be unique and strictly increasing
# within a marketing version, and App Store Connect never frees one once consumed. So
# ask it what it already has rather than guess: any counter or clock can collide or run
# backwards between trigger paths, and a consumed number can never be reclaimed.
#
# Set IOS_BUILD_NUMBER=N to skip the query -- builds that never upload (CI verification,
# local testing) should, since the query needs App Store Connect credentials.
IOS_EXPORT_OPTIONS ?= ios/ExportOptions.plist
IOS_IPA_DIR ?= build/ios/ipa

# The bare `export` at the top of this file (active whenever .env exists) pushes every
# make variable into recipe environments, FLUTTER_BUILD_MODE ?= debug included. Flutter's
# xcode_backend reads FLUTTER_BUILD_MODE before falling back to CONFIGURATION, so an
# archive would emit debug artifacts while xcodebuild really did run -configuration
# Release -- producing an IPA that installs from TestFlight and then refuses to launch.
.PHONY: build/frontend/ios/ipa
build/frontend/ios/ipa: FLUTTER_BUILD_MODE := release
build/frontend/ios/ipa: check/frontend/ios/release ## Build a signed iOS IPA for the App Store
	# Xcode open on this workspace can contend with the CLI archive over DerivedData and
	# produce "accessing build database ... disk I/O error". Warn, do not block.
	if pgrep -qx Xcode >/dev/null; then
		echo "Warning: Xcode is running. Quit it if the archive fails on DerivedData I/O."
	fi
	# Start from a clean slate so no stale intermediate can be reused.
	# Set IOS_SKIP_CLEAN=1 when iterating on signing or export settings.
	if [ -z "$(IOS_SKIP_CLEAN)" ]; then
		flutter clean
	fi
	flutter pub get
	# assets/sbom_flutter.json is declared in pubspec.yaml but generated, not committed
	# (see .gitignore). Without it the archive dies late in
	# release_ios_bundle_flutter_assets with "Failed to bundle asset files".
	$(MAKE) generate/frontend/sbom
	if [ -z "$(BUILD_NAME)" ]; then
		echo "Error: no git tag found to derive the app version from."
		echo "  The version comes from the most recent tag, for example v0.31.1."
		echo "  Fix: git fetch --tags   (CI needs fetch-tags on actions/checkout)"
		echo "       or pass BUILD_NAME=X.Y.Z explicitly."
		exit 1
	fi
	if [ -n "$(IOS_BUILD_NUMBER)" ]; then
		build_number="$(IOS_BUILD_NUMBER)"
	else
		# Diagnostics go to stderr, so this captures just the number.
		build_number="$$(scripts/ios-next-build-number.bash --version "$(BUILD_NAME)")"
	fi
	echo "Building $(BUILD_NAME) ($$build_number)"
	flutter build ipa \
		--release \
		--export-options-plist=$(IOS_EXPORT_OPTIONS) \
		--build-name=$(BUILD_NAME) \
		--build-number="$$build_number"
	ipa="$$(ls -t $(IOS_IPA_DIR)/*.ipa 2>/dev/null | head -1)"
	if [ -z "$$ipa" ]; then
		echo "Error: no IPA was produced in $(IOS_IPA_DIR)."
		echo "Check the xcodebuild output above; a signing failure is the usual cause."
		echo "Run 'make check/frontend/ios/release' to verify signing prerequisites."
		exit 1
	fi
	$(MAKE) check/frontend/ios/ipa IOS_IPA="$$ipa"
	echo "Built $$ipa"
	echo "Next: make publish/frontend/ios"

.PHONY: check/frontend/ios/ipa
check/frontend/ios/ipa: ## Verify an IPA is a real release build (IOS_IPA=path)
	ipa="$(IOS_IPA)"
	if [ -z "$$ipa" ]; then
		ipa="$$(ls -t $(IOS_IPA_DIR)/*.ipa 2>/dev/null | head -1)"
	fi
	if [ -z "$$ipa" ] || [ ! -f "$$ipa" ]; then
		echo "Error: no IPA to check. Run 'make build/frontend/ios/ipa' first."
		exit 1
	fi
	# A debug Flutter build ships a JIT kernel blob and a stub App binary. Such a build
	# uploads and installs fine, then refuses to launch from the home screen or TestFlight.
	if unzip -l "$$ipa" | grep -q "kernel_blob.bin"; then
		echo "Error: $$ipa is a DEBUG build (contains flutter_assets/kernel_blob.bin)."
		echo "  It would install from TestFlight and then refuse to launch."
		echo "  Cause: FLUTTER_BUILD_MODE leaked into the environment as 'debug', or a"
		echo "         stale debug intermediate was reused. Check: make --eval='p:; @env |"
		echo "         grep FLUTTER_BUILD_MODE' p"
		exit 1
	fi
	if ! unzip -l "$$ipa" | grep -q "App.framework/App"; then
		echo "Error: $$ipa has no App.framework/App binary."
		exit 1
	fi
	echo "OK: $$ipa is a release build."

.PHONY: check/frontend/ios/release
check/frontend/ios/release: ## Check iOS App Store release prerequisites
	failed=0
	if [ "$(UNAME_S)" != "Darwin" ]; then
		echo "Error: iOS release builds require macOS (found $(UNAME_S))."
		exit 1
	fi
	if ! xcode-select -p >/dev/null 2>&1; then
		echo "Missing: Xcode command line tools. Run 'make setup/ios' first."
		failed=1
	fi
	if [ ! -f "$(IOS_EXPORT_OPTIONS)" ]; then
		echo "Missing: $(IOS_EXPORT_OPTIONS)."
		failed=1
	fi
	if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Distribution"; then
		echo "Missing: an 'Apple Distribution' signing identity in your keychain."
		echo "  Fix: open Xcode > Settings > Accounts, sign in with the Apple Developer"
		echo "       account for team 4NK7MWUA57, then 'Manage Certificates' > '+' >"
		echo "       'Apple Distribution'."
		failed=1
	fi
	if [ ! -d "$$HOME/Library/MobileDevice/Provisioning Profiles" ]; then
		echo "Warning: no provisioning profiles installed yet. Xcode will fetch an App Store"
		echo "         profile automatically on the first archive if the bundle ID"
		echo "         org.autobutler.quark is registered in App Store Connect."
	fi
	if [ $$failed -ne 0 ]; then
		echo
		echo "iOS release prerequisites are not satisfied."
		exit 1
	fi
	echo "iOS release prerequisites OK."

.PHONY: publish/frontend/ios
publish/frontend/ios: ## Upload the iOS IPA to App Store Connect
	ipa="$$(ls -t $(IOS_IPA_DIR)/*.ipa 2>/dev/null | head -1)"
	if [ -z "$$ipa" ]; then
		echo "Error: no IPA found in $(IOS_IPA_DIR). Run 'make build/frontend/ios/ipa' first."
		exit 1
	fi
	if [ -z "$$APP_STORE_CONNECT_KEY_ID" ] || [ -z "$$APP_STORE_CONNECT_ISSUER_ID" ]; then
		echo "Error: APP_STORE_CONNECT_KEY_ID and APP_STORE_CONNECT_ISSUER_ID must be set."
		echo "  Create an API key at https://appstoreconnect.apple.com/access/integrations/api"
		echo "  with the 'App Manager' role, then place the downloaded .p8 at:"
		echo "    ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8"
		echo "  and export both variables (or add them to .env)."
		exit 1
	fi
	xcrun altool --upload-app \
		--type ios \
		--file "$$ipa" \
		--apiKey "$$APP_STORE_CONNECT_KEY_ID" \
		--apiIssuer "$$APP_STORE_CONNECT_ISSUER_ID"
	echo "Uploaded $$ipa to App Store Connect."
	echo "Next: the build appears under TestFlight after processing (usually 5-30 minutes)."


# Google Play distribution. Android's versionCode is a monotonic int32: Play rejects any
# upload whose code is not strictly above the highest it has already accepted, and never
# frees one. Flutter derives versionCode by stripping non-digits from --build-number, so
# passing the version alone would yield 331 for 0.33.1 and then 100 for 1.0.0 -- going
# BACKWARDS at the 0.x boundary and locking the app out of Play permanently.
#
# Compute it positionally instead. major*10000 + minor*100 + patch is monotonic across
# that boundary and stays far below the 2100000000 cap (up to version 209999.99.99).
# Override with ANDROID_BUILD_NUMBER=N to get above a code Play has already seen.
#
# := not ?=, for the reason #1727 fixed the other shell-backed variables: a recursive
# definition re-runs its $(shell ...) on every expansion, and the bare `export` above
# forces one per recipe. This one runs two subprocesses each time, since $(BUILD_NAME)
# is itself a shell call. $(or ...) keeps an environment or command-line override winning,
# which a bare := would have silently dropped.
ANDROID_BUILD_NUMBER := $(or $(ANDROID_BUILD_NUMBER),$(shell echo "$(BUILD_NAME)" | awk -F. '{printf "%d", ($$1*10000)+($$2*100)+$$3}'))
ANDROID_AAB_DIR ?= build/app/outputs/bundle/release
ANDROID_APK_DIR ?= build/app/outputs/flutter-apk
ANDROID_KEY_PROPERTIES := android/key.properties
# Release artifacts are copied here under their published names. Obtainium matches
# GitHub Release assets by regex, so the APK name has to stay predictable across
# releases -- see docs/android-release.md.
ANDROID_DIST_DIR ?= build/android-release
ANDROID_TRACK ?= internal

# .SILENT: at the top of this file means a build prints almost nothing until it finishes.
# FLUTTER_VERBOSE=1 passes --verbose through to Flutter and Gradle when you need to see
# why one is stuck or failing.
FLUTTER_VERBOSE ?=

# FLUTTER_BUILD_MODE is pinned here for the same reason as build/frontend/ios/ipa: the
# bare `export` at the top of this file pushes every make variable into recipe
# environments, and Flutter's build backend reads FLUTTER_BUILD_MODE in preference to the
# real configuration. This target is one of the two that hardcode --release, so it is one
# of the two that can diverge. See docs/android-release.md.
.PHONY: build/frontend/android/aab
build/frontend/android/aab: FLUTTER_BUILD_MODE := release
build/frontend/android/aab: check/frontend/android/release check/frontend/android/cmdline-tools generate/frontend/sbom ## Build a signed Android AAB for Google Play
	echo "Building $(BUILD_NAME) (versionCode $(ANDROID_BUILD_NUMBER))"
	flutter build appbundle \
		$(if $(FLUTTER_VERBOSE),--verbose,) \
		--release \
		--build-name=$(BUILD_NAME) \
		--build-number=$(ANDROID_BUILD_NUMBER)
	aab="$$(ls -t $(ANDROID_AAB_DIR)/*.aab 2>/dev/null | head -1)"
	if [ -z "$$aab" ]; then
		echo "Error: no AAB was produced in $(ANDROID_AAB_DIR)."
		echo "  Check the Gradle output above; a signing failure is the usual cause."
		echo "  Run 'make check/frontend/android/release' to verify the prerequisites."
		exit 1
	fi
	$(MAKE) check/frontend/android/aab ANDROID_AAB="$$aab"
	mkdir -p $(ANDROID_DIST_DIR)
	cp "$$aab" "$(ANDROID_DIST_DIR)/quark-v$(BUILD_NAME).aab"
	echo "Built $(ANDROID_DIST_DIR)/quark-v$(BUILD_NAME).aab"
	echo "Next: upload it in the Play Console. See docs/android-release.md."

.PHONY: check/frontend/android/aab
check/frontend/android/aab: ## Verify an AAB is a real release build (ANDROID_AAB=path)
	echo "==> check/frontend/android/aab"
	aab="$(ANDROID_AAB)"
	if [ -z "$$aab" ]; then
		aab="$$(ls -t $(ANDROID_AAB_DIR)/*.aab 2>/dev/null | head -1)"
	fi
	if [ -z "$$aab" ] || [ ! -f "$$aab" ]; then
		echo "Error: no AAB to check. Run 'make build/frontend/android/aab' first."
		exit 1
	fi
	# A debug Flutter build ships a JIT kernel blob instead of AOT machine code. It
	# uploads and installs fine, then refuses to launch. The iOS equivalent of this
	# reached TestFlight once; see docs/android-release.md.
	if unzip -l "$$aab" | grep -q "kernel_blob.bin"; then
		echo "Error: $$aab is a DEBUG build (contains flutter_assets/kernel_blob.bin)."
		echo "  It would install from Play and then refuse to launch."
		echo "  Cause: FLUTTER_BUILD_MODE leaked into the environment as 'debug', or a"
		echo "         stale debug intermediate was reused. Check: make --eval='p:; @env |"
		echo "         grep FLUTTER_BUILD_MODE' p"
		exit 1
	fi
	if ! unzip -l "$$aab" | grep -qE "base/lib/[^/]+/libapp\.so"; then
		echo "Error: $$aab has no base/lib/*/libapp.so (AOT-compiled Dart)."
		echo "  A release build carries one shared library per ABI. Rebuild with"
		echo "  'make build/frontend/android/aab'."
		exit 1
	fi
	echo "OK: $$aab is a release build."

# Only `flutter build appbundle` needs this: it inspects the finished bundle for debug
# symbols using apkanalyzer, which ships in cmdline-tools. Without it the build fails at
# the very end -- after a full Gradle run -- with "failed to strip debug symbols from
# native libraries", which points at the NDK rather than at the missing package.
# `flutter build apk` does no such check, so the APK target does not depend on this.
.PHONY: check/frontend/android/cmdline-tools
check/frontend/android/cmdline-tools: ## Check the Android SDK has cmdline-tools (AAB builds only)
	echo "==> check/frontend/android/cmdline-tools"
	sdk="$$ANDROID_HOME"
	[ -n "$$sdk" ] || sdk="$$ANDROID_SDK_ROOT"
	[ -n "$$sdk" ] || sdk="$$(sed -n 's/^sdk.dir=//p' android/local.properties 2>/dev/null | head -1)"
	if [ -n "$$sdk" ] && [ ! -d "$$sdk/cmdline-tools" ]; then
		echo "Missing: Android cmdline-tools in $$sdk."
		echo "  flutter build appbundle needs apkanalyzer from it to verify the finished"
		echo "  bundle, and fails only at the end of a full Gradle build without it."
		echo "  Fix: Android Studio > Settings > Languages & Frameworks > Android SDK >"
		echo "       SDK Tools > tick 'Android SDK Command-line Tools', or"
		echo "       sdkmanager --install 'cmdline-tools;latest'"
		echo
		echo "  'make build/frontend/android/apk' does not need it."
		exit 1
	fi

.PHONY: check/frontend/android/release
check/frontend/android/release: ## Check Android Play release prerequisites
	echo "==> check/frontend/android/release"
	failed=0
	if [ -z "$(BUILD_NAME)" ]; then
		echo "Error: no git tag found to derive the app version from."
		echo "  The version comes from the most recent tag, for example v0.33.1."
		echo "  Fix: git fetch --tags   (CI needs fetch-tags on actions/checkout)"
		echo "       or pass BUILD_NAME=X.Y.Z explicitly."
		failed=1
	fi
	if ! echo "$(ANDROID_BUILD_NUMBER)" | grep -qE '^[1-9][0-9]*$$'; then
		echo "Error: versionCode resolved to '$(ANDROID_BUILD_NUMBER)', which Play will reject."
		echo "  It is derived from BUILD_NAME=$(BUILD_NAME) as major*10000+minor*100+patch."
		echo "  Fix: pass ANDROID_BUILD_NUMBER=N explicitly."
		failed=1
	fi
	if [ ! -f "$(ANDROID_KEY_PROPERTIES)" ]; then
		echo "Missing: $(ANDROID_KEY_PROPERTIES)."
		echo "  Without it the release build is signed with the Android debug key, which"
		echo "  Play rejects on upload."
		echo "  Fix: create the upload keystore and key.properties -- see the 'Signing key'"
		echo "       section of docs/android-release.md."
		echo "  In CI this file is written by scripts/android-ci-signing.bash."
		failed=1
	else
		# Java's Properties.load tolerates whitespace around the key, so these checks must
		# too -- otherwise they reject a key.properties that Gradle reads perfectly well.
		for key in storeFile storePassword keyAlias keyPassword; do
			if ! grep -qE "^[[:space:]]*$$key[[:space:]]*=" "$(ANDROID_KEY_PROPERTIES)"; then
				echo "Missing: '$$key=' in $(ANDROID_KEY_PROPERTIES)."
				echo "  All four of storeFile, storePassword, keyAlias and keyPassword are required."
				failed=1
			fi
		done
		store="$$(sed -n 's/^[[:space:]]*storeFile[[:space:]]*=[[:space:]]*//p' "$(ANDROID_KEY_PROPERTIES)" | head -1)"
		# A bare filename in key.properties resolves against android/, which is what
		# rootProject.file() does in android/app/build.gradle.kts.
		case "$$store" in
			/*) ;;
			*) store="android/$$store" ;;
		esac
		if [ -n "$$store" ] && [ ! -r "$$store" ]; then
			echo "Missing: keystore '$$store', named by storeFile= in $(ANDROID_KEY_PROPERTIES)."
			echo "  Fix: correct storeFile=, or regenerate the keystore per docs/android-release.md."
			failed=1
		fi
	fi
	if [ $$failed -ne 0 ]; then
		echo
		echo "Android release prerequisites are not satisfied."
		exit 1
	fi
	echo "Android release prerequisites OK."

# A universal APK, not per-ABI splits. Obtainium tracks a GitHub Release by matching one
# asset name with a regex, and splits would give it three to choose between. The extra
# size only affects direct downloads; Play serves per-device APKs from the AAB anyway.
# FLUTTER_BUILD_MODE is pinned for the same reason as the AAB target above.
.PHONY: build/frontend/android/apk
build/frontend/android/apk: FLUTTER_BUILD_MODE := release
build/frontend/android/apk: check/frontend/android/release generate/frontend/sbom ## Build a signed universal Android APK
	echo "Building $(BUILD_NAME) (versionCode $(ANDROID_BUILD_NUMBER))"
	flutter build apk \
		$(if $(FLUTTER_VERBOSE),--verbose,) \
		--release \
		--build-name=$(BUILD_NAME) \
		--build-number=$(ANDROID_BUILD_NUMBER)
	apk="$$(ls -t $(ANDROID_APK_DIR)/*.apk 2>/dev/null | head -1)"
	if [ -z "$$apk" ]; then
		echo "Error: no APK was produced in $(ANDROID_APK_DIR)."
		echo "  Check the Gradle output above; a signing failure is the usual cause."
		echo "  Run 'make check/frontend/android/release' to verify the prerequisites."
		exit 1
	fi
	$(MAKE) check/frontend/android/apk ANDROID_APK="$$apk"
	mkdir -p $(ANDROID_DIST_DIR)
	cp "$$apk" "$(ANDROID_DIST_DIR)/quark-v$(BUILD_NAME)-universal.apk"
	echo "Built $(ANDROID_DIST_DIR)/quark-v$(BUILD_NAME)-universal.apk"

.PHONY: check/frontend/android/apk
check/frontend/android/apk: ## Verify an APK is a real release build (ANDROID_APK=path)
	echo "==> check/frontend/android/apk"
	apk="$(ANDROID_APK)"
	if [ -z "$$apk" ]; then
		apk="$$(ls -t $(ANDROID_APK_DIR)/*.apk 2>/dev/null | head -1)"
	fi
	if [ -z "$$apk" ] || [ ! -f "$$apk" ]; then
		echo "Error: no APK to check. Run 'make build/frontend/android/apk' first."
		exit 1
	fi
	# Same debug-build guard as the AAB check; an APK just nests the entries one level
	# higher. A debug APK installs from a direct download and then refuses to launch.
	if unzip -l "$$apk" | grep -q "kernel_blob.bin"; then
		echo "Error: $$apk is a DEBUG build (contains flutter_assets/kernel_blob.bin)."
		echo "  It would install and then refuse to launch."
		echo "  Cause: FLUTTER_BUILD_MODE leaked into the environment as 'debug', or a"
		echo "         stale debug intermediate was reused. Check: make --eval='p:; @env |"
		echo "         grep FLUTTER_BUILD_MODE' p"
		exit 1
	fi
	if ! unzip -l "$$apk" | grep -qE "lib/[^/]+/libapp\.so"; then
		echo "Error: $$apk has no lib/*/libapp.so (AOT-compiled Dart)."
		echo "  A release build carries one shared library per ABI. Rebuild with"
		echo "  'make build/frontend/android/apk'."
		exit 1
	fi
	echo "OK: $$apk is a release build."

.PHONY: publish/frontend/android
publish/frontend/android: ## Upload the Android AAB to Google Play (ANDROID_TRACK=internal)
	echo "==> publish/frontend/android"
	scripts/android-publish.bash \
		--track "$(ANDROID_TRACK)" \
		$(if $(ANDROID_AAB),--aab "$(ANDROID_AAB)",) \
		$(if $(ANDROID_PUBLISH_DRY_RUN),--dry-run,)

.PHONY: build/frontend/web
build/frontend/web: internal/server/public/stub.txt generate/frontend/sbom ## Build web app
	flutter build web --$(FLUTTER_BUILD_MODE) $(if $(BUILD_NAME),--build-name=$(BUILD_NAME),)
	cp -R ./build/web/. ./internal/server/public/

.PHONY: build/provisioning
build/provisioning: ## Build provisioning service
	mkdir -p ./build
	$(GO) build -o ./build/quark-provisioning ./cmd/provisioning/

.PHONY: build/lsusb
build/lsusb: ## Build lsusb utility
	$(GO) build -o ./build/lsusb ./cmd/lsusb/main.go

# The image downloads a published release rather than building from source, so it can only
# be built for a version that has actually been tagged and released. Override with
# BUILD_NAME=X.Y.Z. The release workflow builds the multi-arch image and pushes it; this
# target is the local host-architecture build.
DOCKER_IMAGE ?= ghcr.io/autobutler-org/quark
DOCKER_VOLUME ?= quark-data
DOCKER_CONTAINER ?= quark-serve
# Empty uses the $(DOCKER_VOLUME) named volume. Set it to an absolute host path to bind-mount that
# directory as the Quark root instead -- see docs/container.md for the uid it has to be owned by.
DOCKER_DATA ?=
# The same port serve/backend uses. Collides if both run at once; DOCKER_PORT=9000 overrides.
DOCKER_PORT ?= 8080

.PHONY: check/docker
check/docker: ## Check that the Docker daemon is reachable
	if ! docker info >/dev/null 2>&1; then
		echo "Error: cannot talk to the Docker daemon."
		echo "  Fix: start Docker Desktop, or install Docker from https://docs.docker.com/get-docker/"
		exit 1
	fi

.PHONY: build/docker
build/docker: check/docker ## Build the container image for a released version
	if [ -z "$(BUILD_NAME)" ]; then
		echo "Error: no git tag found to derive the Quark version from."
		echo "  The version comes from the most recent tag, for example v0.36.2."
		echo "  Fix: git fetch --tags"
		echo "       or pass BUILD_NAME=X.Y.Z explicitly."
		exit 1
	fi
	echo "Building $(DOCKER_IMAGE):$(BUILD_NAME)"
	docker build --build-arg VERSION=$(BUILD_NAME) -t $(DOCKER_IMAGE):$(BUILD_NAME) .

.PHONY: emulate
emulate: ## Emulate mobile device
ifeq ($(UNAME_S),Linux)
	make emulate/android
else ifeq ($(UNAME_S),Darwin)
	make emulate/ios
else
	$(error "Unsupported OS: $(UNAME_S)")
endif

ANDROID_DEVICE_ID ?= Pixel_6
IOS_DEVICE_ID ?= apple_ios_simulator

.PHONY: emulate/android
emulate/android: ## Emulate Android device
	flutter emulators --launch $(ANDROID_DEVICE_ID)

.PHONY: emulate/ios
emulate/ios: ## Emulate iOS device
	flutter emulators --launch $(IOS_DEVICE_ID)

.PHONY: generate
generate: generate/backend generate/frontend ## Generate files

.PHONY: generate/backend
generate/backend: generate/backend/sqlc generate/backend/swagger ## Generate backend files

.PHONY: generate/backend/sqlc
generate/backend/sqlc: ## Generate sqlc files
	sqlc generate

.PHONY: generate/backend/swagger
generate/backend/swagger: ## Generate Swagger docs
	swag init -g ./cmd/quark/main.go -o ./docs/swagger --parseInternal

.PHONY: generate/frontend
generate/frontend: generate/frontend/icons generate/frontend/quark-icons generate/frontend/sbom generate/frontend/widget-docs ## Generate frontend files

.PHONY: generate/frontend/pub-get
generate/frontend/pub-get: ## Refresh the workspace resolution for `dart run`
	# `dart run` re-resolves whenever it decides the workspace resolution is
	# stale, and plain `dart pub get` cannot resolve a workspace that needs the
	# Flutter SDK. Refresh with `flutter pub get` first so the targets below
	# always find an up-to-date resolution.
	flutter pub get

.PHONY: generate/frontend/icons
generate/frontend/icons: generate/frontend/pub-get ## Generate app icons
	dart run flutter_launcher_icons

.PHONY: generate/frontend/quark-icons
generate/frontend/quark-icons: ## Regenerate QuarkIcons.ttf from SVGs using fantasticon
	npx fantasticon packages/quark_icons/svgs \
		--output packages/quark_icons/fonts \
		--font-types ttf \
		--name QuarkIcons \
		--config packages/quark_icons/.fantasticonrc.json \
		--normalize

.PHONY: generate/frontend/widget-docs
generate/frontend/widget-docs: ## Regenerate the widget gallery's docs from /// class comments
	$(MAKE) -C packages/quark_widgets generate/docs

.PHONY: generate/frontend/sbom
generate/frontend/sbom: generate/frontend/pub-get ## Generate Flutter SBOM asset from pubspec.lock
	dart run scripts/generate_flutter_sbom.dart

DEPLOY_HOST ?= quark
DEPLOY_PATH ?= ~/quark

.PHONY: remote-deploy
remote-deploy: build ## Build and deploy to a remote host via scp, then run the binary
	scp $(EXE) $(DEPLOY_HOST):$(DEPLOY_PATH)
	ssh $(DEPLOY_HOST) "pkill -f '$(DEPLOY_PATH) serve' || true; nohup $(DEPLOY_PATH) serve > ~/quark.log 2>&1 &"

.PHONY: drive
drive: ## Create and mount a new MyDrive DMG (auto-numbered: MyDrive, MyDrive2, MyDrive3, …)
	@if ! test -d /Volumes/MyDrive; then \
		N=""; \
	else \
		i=2; \
		while test -d /Volumes/MyDrive$$i; do i=$$((i+1)); done; \
		N=$$i; \
	fi; \
	NAME="MyDrive$$N"; \
	FILE="$$HOME/Desktop/mydrive$$N.dmg"; \
	echo "Creating $$FILE (volume: $$NAME)..."; \
	hdiutil create -size 100m -fs HFS+ -volname "$$NAME" "$$FILE"; \
	hdiutil attach "$$FILE"

.PHONY: unmount-drive
unmount-drive: ## Detach the highest-numbered MyDrive volume currently mounted
	@highest_num=-1; \
	highest_name=""; \
	for name in $$(ls /Volumes/ 2>/dev/null | grep -E '^MyDrive[0-9]*$$'); do \
		num=$$(echo "$$name" | sed 's/MyDrive//'); \
		if [ -z "$$num" ]; then num=0; fi; \
		if [ "$$num" -gt "$$highest_num" ]; then \
			highest_num=$$num; \
			highest_name=$$name; \
		fi; \
	done; \
	if [ -z "$$highest_name" ]; then \
		echo "No MyDrive volumes mounted."; \
		exit 1; \
	fi; \
	echo "Detaching /Volumes/$$highest_name..."; \
	hdiutil detach "/Volumes/$$highest_name"

.PHONY: serve/backend
serve/backend: generate/backend ## Serve backend over plain HTTP on :8080 (insecure)
	$(SUDO) env QUARK_INSECURE=true $(GO) run $(GO_LDFLAGS) $(ENTRYPOINT) serve

.PHONY: serve/backend/secure
serve/backend/secure: generate/backend ## Serve backend over HTTPS on :443 (self-signed)
	$(SUDO) $(GO) run $(GO_LDFLAGS) $(ENTRYPOINT) serve

# State persists in the $(DOCKER_VOLUME) volume between runs, on purpose: a fresh volume every
# time would drop the account created on first launch. `docker volume rm $(DOCKER_VOLUME)` resets.
.PHONY: serve/docker
serve/docker: check/docker ## Serve the container image on :$(DOCKER_PORT), state in a named volume
	if [ -z "$(BUILD_NAME)" ]; then
		echo "Error: no git tag found to derive the Quark version from."
		echo "  Fix: git fetch --tags, or pass BUILD_NAME=X.Y.Z explicitly."
		exit 1
	fi
	# A relative -v source is not an error to docker: it quietly creates a named volume instead of
	# mounting the directory, and Quark then comes up empty with nothing on screen to explain it.
	data="$(DOCKER_DATA)"
	if [ -n "$$data" ]; then
		data="$${data/#\~/$$HOME}"
		case "$$data" in
			/*) ;;
			*)
				echo "Error: DOCKER_DATA=$(DOCKER_DATA) is not an absolute path."
				echo "  Docker would create a named volume rather than mount the directory."
				echo "  Fix: make serve/docker DOCKER_DATA=$$PWD/$(DOCKER_DATA)"
				exit 1
				;;
		esac
		if [ ! -d "$$data" ]; then
			echo "Error: DOCKER_DATA=$$data is not an existing directory."
			echo "  Fix: mkdir -p $$data"
			exit 1
		fi
		echo "Data directory: $$data"
	fi
	if ! docker image inspect $(DOCKER_IMAGE):$(BUILD_NAME) >/dev/null 2>&1; then
		echo "Error: no local image $(DOCKER_IMAGE):$(BUILD_NAME)."
		echo "  Fix: make build/docker, or docker pull $(DOCKER_IMAGE):$(BUILD_NAME)"
		exit 1
	fi
	# --rm does not fire if the daemon restarts or the container is killed, so a dead one can
	# outlive its run. It holds nothing worth keeping -- the state is in the volume -- so clear it
	# rather than making the user run a command we could run. A *running* one is someone's live
	# session, which docker rm -f would kill, so that still stops here.
	case "$$(docker inspect -f '{{.State.Running}}' $(DOCKER_CONTAINER) 2>/dev/null)" in
		true)
			echo "Error: $(DOCKER_CONTAINER) is already running at http://localhost:$(DOCKER_PORT)."
			echo "  Fix: make clean/docker to stop it, or DOCKER_PORT=<port> to run a second one."
			exit 1
			;;
		false)
			echo "Removing the $(DOCKER_CONTAINER) container left over from an earlier run"
			docker rm -f $(DOCKER_CONTAINER) >/dev/null
			;;
	esac
	echo "Quark is at http://localhost:$(DOCKER_PORT)"
	docker run -it --rm --name $(DOCKER_CONTAINER) -p $(DOCKER_PORT):8080 -v "$${data:-$(DOCKER_VOLUME)}:/var/lib/quark" $(DOCKER_IMAGE):$(BUILD_NAME)

.PHONY: serve/frontend
serve/frontend: serve/frontend/web ## Serve frontend

.PHONY: serve/frontend/mobile
serve/frontend/mobile: generate/frontend ## Serve mobile frontend
	flutter run $(FLUTTER_RUN_DEFINES)

.PHONY: serve/frontend/web
serve/frontend/web: generate/frontend ## Serve web frontend
	flutter run \
		-d web-server \
		$(FLUTTER_RUN_DEFINES)

PRINT_COVERAGE ?= 0

.PHONY: test
test: test/unit

PERF_PORT ?= 8080
PERF_BASE_URL ?= http://127.0.0.1:$(PERF_PORT)
PERF_SUMMARY_WRK_DIRS ?= test-results/performance
PERF_FIXTURE_TARGET_DIR ?= $(HOME)/quark/data/files

.PHONY: test/perf/generate-files
test/perf/generate-files: ## Generate file fixtures under a target files directory for performance testing
	bash ./test/performance/generate_files.sh "$(PERF_FIXTURE_TARGET_DIR)"

.PHONY: test/perf/load
test/perf/load: build/backend ## Run local wrk load profile against a temporary local backend
	mkdir -p test-results/performance
	$(MAKE) test/perf/generate-files PERF_FIXTURE_TARGET_DIR="$(PERF_FIXTURE_TARGET_DIR)"
	PORT=$(PERF_PORT) QUARK_INSECURE=true ./build/quark serve > test-results/performance/server-load.log 2>&1 &
	SERVER_PID=$$!
	trap 'kill $$SERVER_PID 2>/dev/null || true' EXIT
	export QUARK_BASE_URL=$(PERF_BASE_URL)
	export PERF_FIXTURE_TARGET_DIR="$(PERF_FIXTURE_TARGET_DIR)"
	export TEST_DURATION_THREADS=2
	export TEST_DURATION_CONCURRENCY=15
	export TEST_DURATION_DURATION=10s
	export TEST_UPLOAD_CONCURRENCY=4
	export TEST_UPLOAD_COUNT=8
	./test/performance/test.sh

.PHONY: test/perf/stress
test/perf/stress: build/backend ## Run local wrk stress profile against a temporary local backend
	mkdir -p test-results/performance
	$(MAKE) test/perf/generate-files PERF_FIXTURE_TARGET_DIR="$(PERF_FIXTURE_TARGET_DIR)"
	PORT=$(PERF_PORT) QUARK_INSECURE=true ./build/quark serve > test-results/performance/server-stress.log 2>&1 &
	SERVER_PID=$$!
	trap 'kill $$SERVER_PID 2>/dev/null || true' EXIT
	export QUARK_BASE_URL=$(PERF_BASE_URL)
	export PERF_FIXTURE_TARGET_DIR="$(PERF_FIXTURE_TARGET_DIR)"
	export TEST_DURATION_THREADS=4
	export TEST_DURATION_CONCURRENCY=50
	export TEST_DURATION_DURATION=30s
	export TEST_UPLOAD_CONCURRENCY=10
	export TEST_UPLOAD_COUNT=20
	./test/performance/test.sh

.PHONY: test/perf/summary
test/perf/summary: ## Render the Markdown performance summary
	python3 ./test/performance/render_summary.py \
		$(foreach dir,$(PERF_SUMMARY_WRK_DIRS),--wrk-dir $(dir))

.PHONY: test/unit
test/unit: test/unit/backend test/unit/frontend ## Run unit tests

.PHONY: test/unit/backend
test/unit/backend: internal/server/public/stub.txt ## Run unit tests for backend
	# Generate coverage report for unit tests (excludes integration test packages)
	$(GO) test -v $(shell $(GO) list ./... | grep -v '/internal/server/api/v0/') \
		-coverprofile=coverage.out \
		-covermode=atomic
	# Apply coverage ignore directives
	./scripts/apply-coverage-ignore.bash \
		coverage.out
	# Generate coverage report as HTMl
	$(GO) tool cover \
		-html=coverage.out.ignored \
		-o coverage.html
	# Display coverage summary in terminal
	if [[ "$(PRINT_COVERAGE)" = "1" || "$(PRINT_COVERAGE)" = "true" ]] ; then
		$(GO) tool cover \
			-func=coverage.out.ignored
	fi

.PHONY: test/unit/frontend
test/unit/frontend: generate/frontend ## Run unit tests for frontend
	echo "Testing Quark frontend..."
	flutter test
	for pkg in packages/*/; do
		if [ -f "$$pkg/pubspec.yaml" ] && [ -d "$$pkg/test" ]; then
			echo "Testing $$pkg..."
			$(MAKE) -C "$$pkg" test/unit || exit 1
		fi
	done

.PHONY: test/integration
test/integration: test/integration/backend ## Run integration tests

.PHONY: test/integration/backend
test/integration/backend: internal/server/public/stub.txt ## Run backend integration tests (requires real filesystem, spins up gin engine)
	$(GO) test -v ./internal/server/api/v0/...

.PHONY: coverage
coverage: test/unit/backend ## Run backend tests and print coverage percentage
	$(GO) tool cover \
		-func=coverage.out.ignored | tail -1

.PHONY: tidy
tidy: tidy/flutter tidy/go ## Tidy dependencies

.PHONY: tidy/flutter
tidy/flutter: ## Tidy Flutter dependencies
	# The repo is a Dart pub workspace: one resolution at the root covers the
	# app, every package under packages/, and every example app.
	flutter pub get
ifeq ($(UNAME_S),Darwin)
	cd ios && pod install
endif

.PHONY: tidy/go
tidy/go: ## Tidy go mod
	$(GO) mod tidy

.PHONY: upgrade
upgrade: upgrade/flutter upgrade/go ## Upgrade dependencies

.PHONY: upgrade/flutter
upgrade/flutter: ## Upgrade Flutter dependencies
	flutter pub upgrade
	$(MAKE) tidy/flutter
	$(MAKE) generate/frontend

.PHONY: upgrade/go
upgrade/go: generate/backend ## Upgrade dependencies (go)
	$(GO) get -u ./...
	$(MAKE) tidy/go

.PHONY: watch/backend
watch/backend: build/backend ## Watch backend for changes, plain HTTP on :8080 (insecure)
	$(SUDO) env QUARK_INSECURE=true $(AIR)

.PHONY: watch/backend/secure
watch/backend/secure: build/backend ## Watch backend for changes, HTTPS on :443 (self-signed)
	$(SUDO) $(AIR)

.PHONY: watch/frontend
watch/frontend: generate/frontend ## Watch frontend on web
	echo "Defaulting to web since it supports hot reload..."
	flutter run -d chrome $(FLUTTER_RUN_DEFINES)

##@ Code quality

.PHONY: check
check: check/backend check/frontend check/spelling ## Check code

.PHONY: check/backend
check/backend: generate/backend check/format/go check/lint/go check/lint/sqlc check/migrations ## Check backend code

.PHONY: check/frontend
check/frontend: check/format/flutter check/lint/flutter ## Check frontend code

.PHONY: check/spelling
check/spelling: node_modules ## Check spelling in code and docs
	npm run check:spelling

# The npm scripts run binaries from node_modules/.bin, which a fresh checkout
# does not have — CI installs them in its setup-node step, so only local runs
# hit the bare `cspell: command not found`. Depending on the directory installs
# it on demand and reinstalls whenever the lockfile moves; touch keeps make from
# repeating the install on every target that needs it.
node_modules: package-lock.json
	npm ci
	@touch node_modules

.PHONY: check/go
check/go: check/format/go check/lint/go ## Check Go code

.PHONY: check/sqlc
check/sqlc: check/lint/sqlc ## Check sqlc

.PHONY: check/format
check/format: check/format/flutter check/format/go ## Check code formatting

.PHONY: check/format/flutter
check/format/flutter: ## Check Flutter/Dart code formatting
	dart format --set-exit-if-changed .

.PHONY: check/format/go
check/format/go: ## Check Go code formatting
	if [[ -n $$($(GO) fmt ./...) ]]; then
		exit 1
	fi

.PHONY: check/lint
check/lint: check/lint/flutter check/lint/go check/lint/sqlc ## Check code quality

.PHONY: check/lint/flutter
check/lint/flutter: generate/frontend/icons generate/frontend/sbom ## Lint Flutter/Dart code
	flutter analyze

.PHONY: check/lint/go
check/lint/go: internal/server/public/stub.txt check/structure/go ## Check Go code
	if ! command -v golangci-lint >/dev/null 2>&1; then
		echo "golangci-lint is not installed. Run 'make setup/golangci-lint' first."
		exit 1
	fi
	golangci-lint run ./...

.PHONY: check/structure/go
check/structure/go: ## Check Go package layout conventions (AGENTS.md)
	./scripts/check-go-structure.bash

MIGRATION_BASE_REF ?= origin/main

.PHONY: check/migrations
check/migrations: ## Check DB migrations are numbered above the base branch (MIGRATION_BASE_REF=origin/main)
	./scripts/check-migration-numbers.bash "$(MIGRATION_BASE_REF)"

.PHONY: check/vuln
check/vuln: check/vuln/backend ## Check for known CVEs

.PHONY: check/vuln/backend
check/vuln/backend: ## Check Go module for known CVEs (govulncheck)
	govulncheck ./...

.PHONY: check/lint/sqlc
check/lint/sqlc: ## Check sqlc
	sqlc vet

.PHONY: fix
fix: fix/flutter fix/go ## Fix code issues

.PHONY: fix/flutter
fix/flutter: format/flutter ## Fix Flutter code issues

.PHONY: fix/go
fix/go: tidy/go format/go ## Fix Go code issues

.PHONY: format
format: format/flutter format/go ## Format code

.PHONY: format/flutter
format/flutter: ## Format Flutter/Dart code
	dart format .

.PHONY: format/go
format/go: ## Format Go code
	gofmt -s -w .

##@ Release

.PHONY: release/yank
release/yank: ## Yank a release: remove from Azure + mark GitHub release as pre-release (VERSION=v0.X.Y)
	if [ -z "$(VERSION)" ]; then echo "Error: VERSION is required. Usage: make release/yank VERSION=v0.X.Y"; exit 1; fi
	echo "Yanking $(VERSION) from Azure Blob Storage..."
	az storage blob delete-batch \
		--account-name quarkrelease \
		--source releases \
		--pattern "quark/$(VERSION)/*"
	echo "Marking $(VERSION) as pre-release on GitHub..."
	gh release edit $(VERSION) --prerelease --repo autobutler-org/quark
	echo "✅ $(VERSION) yanked. Ship a patch release ASAP."

##@ Helpers

.PHONY: version
version: ## Print version
	$(GO) run $(GO_LDFLAGS) $(ENTRYPOINT) version

.PHONY: help
help: ## Displays help info
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

env-%: ## Check for env var
	if [ -z "$($*)" ]; then \
		echo "Error: Environment variable '$*' is not set."; \
		exit 1; \
	fi

# ── Azure deployment ────────────────────────────────────────────────────────

## render/headscale: Embed setup-headscale.bash into ARM parameters file.
## Usage: make render/headscale HEADSCALE_DOMAIN=network.quark.org ADMIN_EMAIL=admin.quark.org
## Output: deploy/azure/headscale.rendered.parameters.json (gitignored)

HEADSCALE_DOMAIN ?= network.quark.org

deploy/azure/headscale.rendered.parameters.json: env-HEADSCALE_DOMAIN ## Render ARM parameters file for headscale deployment
	bash deploy/azure/render.bash
.PHONY: render/headscale
render/headscale: deploy/azure/headscale.rendered.parameters.json ## Render ARM parameters file for headscale deployment (alias)

SSH_KEY_PATH ?= ~/.ssh/id_quark-headscale.pub

.PHONY: deploy/headscale
deploy/headscale: deploy/azure/headscale.rendered.parameters.json
	az deployment group create \
	    --resource-group quark-headscale \
	    --template-file ./deploy/azure/headscale.json \
	    --parameters ./$< \
	    --parameters adminPublicKey="$$(cat $(SSH_KEY_PATH))"
