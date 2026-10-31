#!/usr/bin/env bash

# shellcheck source=ci/common.sh
source /tmp/common.sh
base_packages ${BACKEND_PACKAGES} ${FRONTEND_PACKAGES}
install_backend
install_frontend
check_backend
check_frontend

test -x /home/runner/run.sh
