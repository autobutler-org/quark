SHELL := /usr/bin/env
.SHELLFLAGS = bash -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:

.PHONY: clean
clean: clean/dart ## Clean all build and test artifacts

.PHONY: clean/dart
clean/dart: ## Clean Dart package
	rm -rf .dart_tool build

##@ Development

.PHONY: test
test: test/unit ## Run tests

.PHONY: test/unit
test/unit: ## Run unit tests
	dart test $(if $(FLUTTER_TEST_CONCURRENCY),--concurrency=$(FLUTTER_TEST_CONCURRENCY))

.PHONY: tidy
tidy: tidy/dart ## Tidy dependencies

.PHONY: tidy/dart
tidy/dart: ## Tidy Dart package dependencies
	dart pub get

.PHONY: upgrade
upgrade: upgrade/dart ## Upgrade dependencies

.PHONY: upgrade/dart
upgrade/dart: ## Upgrade Dart package and dependencies
	dart pub upgrade
	$(MAKE) tidy/dart

##@ Code quality

.PHONY: check
check: check/format check/lint ## Check code

.PHONY: check/dart
check/dart: check/format/dart check/lint/dart ## Check Dart package code

.PHONY: check/format
check/format: check/format/dart ## Check code formatting

.PHONY: check/format/dart
check/format/dart: ## Check Dart code formatting
	dart format --set-exit-if-changed .

.PHONY: check/lint
check/lint: check/lint/dart ## Check

.PHONY: check/lint/dart
check/lint/dart: ## Lint Dart package code
	dart analyze lib test

.PHONY: fix
fix: fix/dart ## Fix code issues

.PHONY: fix/dart
fix/dart: format/dart ## Fix Dart code issues

.PHONY: format
format: format/dart ## Format code

.PHONY: format/dart
format/dart: ## Format Dart code
	dart format .

##@ Helpers

.PHONY: help
help: ## Displays help info
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

env-%: ## Check for env var
	if [ -z "$($*)" ]; then
		echo "Error: Environment variable '$*' is not set."
		exit 1
	fi
