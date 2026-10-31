#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages
install_backend
check_backend
