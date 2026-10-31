#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages
install_backend
install_frontend
install_runner
check_backend
check_frontend

test -x /home/runner/run.sh
