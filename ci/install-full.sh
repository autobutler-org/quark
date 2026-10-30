#!/usr/bin/env bash
# cspell:words libmpv
# Flutter plus the Linux desktop and AppImage packages.

source /tmp/common.sh
apt-get update
apt-get install -y --no-install-recommends \
	ca-certificates curl git jq sudo unzip zip xz-utils \
	build-essential python3 python3-venv libglu1-mesa
xargs -a /tmp/apt-packages.txt apt-get install -y --no-install-recommends
cleanup_packages
install_node
install_flutter

node --version
flutter --version
command -v cmake
command -v patchelf
