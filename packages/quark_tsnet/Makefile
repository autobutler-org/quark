SHELL := /usr/bin/env
.SHELLFLAGS = bash -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:

.PHONY: clean
clean: ## Clean build and test artifacts
	rm -rf .dart_tool build

##@ Development

.PHONY: test
test: test/unit ## Run tests

.PHONY: test/unit
test/unit: test/unit/go test/unit/dart ## Run Go and Dart unit tests

.PHONY: test/unit/go
test/unit/go: ## Run the bridge's Go tests (in-process control server, no network)
	cd go && go test ./...

.PHONY: test/unit/dart
test/unit/dart: ## Run the Dart tests (the build hook compiles the bridge for the host)
	dart test

##@ Code quality

.PHONY: check
check: check/format check/lint ## Check code

.PHONY: check/format
check/format: ## Check Dart and Go formatting
	dart format --set-exit-if-changed .
	test -z "$$(gofmt -l go)" || { gofmt -l go; echo "Run 'make fix'."; exit 1; }

.PHONY: check/lint
check/lint: ## Lint Dart and Go code
	dart analyze lib test hook
	cd go && go vet ./...

.PHONY: fix
fix: ## Format Dart and Go code
	dart format .
	gofmt -s -w go

##@ Helpers

.PHONY: help
help: ## Displays help info
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m\033[0m\n"} /^[a-zA-Z_\/-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
