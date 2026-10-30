#!/usr/bin/env bash
# Flutter and Node for the web, Android, and frontend test jobs.

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages libglu1-mesa
install_node
install_flutter

node --version
flutter --version
