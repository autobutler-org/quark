#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages
install_backend
check_backend
# Last, so it owns whatever the checks wrote.
install_runner

test -x /home/runner/run.sh
