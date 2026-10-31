#!/usr/bin/env bash
# Go, Node, Docker, the backend CI tools, and the Actions runner. No Flutter.

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages wrk
install_go
install_node
install_docker
install_go_tools
install_runner

go version
node --version
docker --version
golangci-lint version
govulncheck -version
sqlc version
swag --version
command -v wrk
test -x /home/runner/run.sh
