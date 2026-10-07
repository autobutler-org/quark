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

.PHONY: test
test: test/unit ## Run tests

.PHONY: test/unit
test/unit: ## Run unit tests
	echo "Testing quark_slides package..."
	flutter test $(if $(FLUTTER_TEST_CONCURRENCY),--concurrency=$(FLUTTER_TEST_CONCURRENCY))

.PHONY: tidy
tidy: tidy/flutter ## Tidy dependencies

.PHONY: tidy/flutter
tidy/flutter: ## Tidy Flutter dependencies
	# The repo is a pub workspace: this resolves the whole workspace.
	flutter pub get

##@ Code quality

.PHONY: check
check: check/format check/lint ## Check code

.PHONY: check/format
check/format: check/format/flutter ## Check code formatting

.PHONY: check/format/flutter
check/format/flutter: ## Check Flutter/Dart code formatting
	dart format --set-exit-if-changed .

.PHONY: check/lint
check/lint: check/lint/flutter ## Check

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

##@ Helpers

.PHONY: help
help: ## Displays help info
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
