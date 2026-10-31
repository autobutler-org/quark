#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages ${BACKEND_PACKAGES}
install_backend
check_backend
