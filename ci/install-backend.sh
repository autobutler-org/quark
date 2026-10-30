#!/usr/bin/env bash
# Go, Node, Docker, and the backend CI tools. No Flutter.

source /tmp/common.sh
base_packages wrk
install_go
install_node
install_docker
install_go_tools

go version
node --version
docker --version
golangci-lint version
govulncheck -version
sqlc version
swag --version
wrk --version
