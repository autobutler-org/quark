#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages ${FRONTEND_PACKAGES}
install_frontend
check_frontend
