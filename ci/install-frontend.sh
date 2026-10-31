#!/usr/bin/env bash
# Flutter, Node, Docker, and the Actions runner for the web, Android, and
# frontend test jobs.

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages libglu1-mesa
install_node
install_flutter
install_docker
install_runner

node --version
flutter --version
docker --version
test -x /home/runner/run.sh
