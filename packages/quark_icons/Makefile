SHELL := /usr/bin/env
.SHELLFLAGS = bash -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:

.PHONY: clean
clean: clean/flutter ## Clean all build and test artifacts

.PHONY: clean/flutter
clean/flutter: ## Clean flutter project
	flutter clean

##@ Development

PLATFORM ?= web
FLUTTER_BUILD_MODE ?= debug

.PHONY: build
build: build/examples/icon_gallery ## Build examples

build/examples/%: env-PLATFORM ## Build example
	cd ./examples/$*
	flutter build $(PLATFORM) --$(FLUTTER_BUILD_MODE)

SERVE_PLATFORM ?= web-server

serve/%: ## Serve example (e.g. make serve/icon_gallery)
	cd ./examples/$*
	flutter run -d $(SERVE_PLATFORM)

watch/%: ## Watch example on web with hot reload (e.g. make watch/icon_gallery)
	cd ./examples/$*
	flutter run -d chrome

##@ Icon generation

.PHONY: generate
generate: generate/icons ## Regenerate all generated files

.PHONY: generate/icons
generate/icons: ## Regenerate QuarkIcons.ttf from SVGs using fantasticon
	npx fantasticon svgs \
		--output fonts \
		--font-types ttf \
		--name QuarkIcons \
		--normalize

##@ Code quality

.PHONY: check
check: check/format check/lint ## Check code

.PHONY: check/format
check/format: check/format/flutter ## Check code formatting

.PHONY: check/format/flutter
check/format/flutter: ## Check Flutter/Dart code formatting
	dart format --set-exit-if-changed .

.PHONY: check/lint
check/lint: check/lint/flutter ## Check linting

.PHONY: check/lint/flutter
check/lint/flutter: ## Lint Flutter/Dart code
	flutter analyze

.PHONY: fix
fix: fix/flutter ## Fix code issues

.PHONY: fix/flutter
fix/flutter: format/flutter ## Fix Flutter code issues

.PHONY: format
format: format/flutter ## Format code

.PHONY: format/flutter
format/flutter: ## Format Flutter/Dart code
	dart format .

##@ Testing

.PHONY: test
test: test/unit ## Run tests

.PHONY: test/unit
test/unit: ## Run unit tests
	flutter test $(if $(FLUTTER_TEST_CONCURRENCY),--concurrency=$(FLUTTER_TEST_CONCURRENCY))

##@ Dependencies

.PHONY: tidy
tidy: tidy/flutter ## Tidy dependencies

.PHONY: tidy/flutter
tidy/flutter: ## Tidy Flutter dependencies
	flutter pub get
	for example in examples/*/; do
		if [ -f "$$example/pubspec.yaml" ]; then
			echo "Running pub get in $$example..."
			cd "$$example"
			flutter pub get
			cd ../..
		fi
	done

.PHONY: upgrade
upgrade: upgrade/flutter ## Upgrade dependencies

.PHONY: upgrade/flutter
upgrade/flutter: ## Upgrade Flutter dependencies
	flutter pub upgrade
	$(MAKE) tidy/flutter

##@ Helpers

.PHONY: help
help: ## Displays help info
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

env-%: ## Check for env var
	if [ -z "$($*)" ]; then
		echo "Error: Environment variable '$*' is not set."
		exit 1
	fi
