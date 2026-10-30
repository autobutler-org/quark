# CI image for Errand. Debian's slim stable image, plus the tools Quark's Linux
# jobs already install on a runner. The workflow passes the versions from the
# repo files. The defaults match those files as of 2026-10-30 so a local build
# without build-args is the same image.
#
# This image is the runner pod, not a nested job container. It has to contain
# the Actions runner, because the scale set starts /home/runner/run.sh. The
# kubelet pulls it from ACR. A job container would make DinD pull a private
# image with no registry login.

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/usr/local/go/bin:/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin \
    GOPATH=/home/runner/go \
    GOCACHE=/home/runner/.cache/go-build \
    GOBIN=/usr/local/bin \
    PUB_CACHE=/home/runner/.pub-cache \
    FLUTTER_HOME=/opt/flutter

# linux/apt-packages.txt is copied into this directory by the workflow before
# docker build. It is the list the Linux bundle job installs.
COPY apt-packages.txt /tmp/apt-packages.txt

RUN bash -euo pipefail -c 'apt-get update \
    && xargs apt-get install -y --no-install-recommends \
        ca-certificates curl git jq sudo unzip zip xz-utils \
        build-essential python3 python3-venv libglu1-mesa wrk \
        < /tmp/apt-packages.txt \
    && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.txt'

ARG TARGETARCH
ARG GO_VERSION=1.27.3
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
ARG GOLANGCI_LINT_VERSION=v2.15.0
ARG GOVULNCHECK_VERSION=v1.9.0
ARG SQLC_VERSION=v1.31.1
ARG SWAG_VERSION=v1.16.6
ARG PROBE_VERSION=v0.14.0
ARG RUNNER_VERSION=2.338.2
ARG DOCKER_VERSION=28.0.4

RUN bash -euo pipefail -c '\
    case "${TARGETARCH}" in \
        amd64) goarch=amd64; nodearch=x64; dockerarch=x86_64; runnerarch=x64 ;; \
        arm64) goarch=arm64; nodearch=arm64; dockerarch=aarch64; runnerarch=arm64 ;; \
        *) echo "unsupported architecture ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${goarch}.tar.gz" | tar -C /usr/local -xz; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${nodearch}.tar.xz" | tar -C /usr/local --strip-components=1 -xJ; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${dockerarch}/docker-${DOCKER_VERSION}.tgz" | tar -xz -C /tmp; \
    install -m 755 /tmp/docker/docker /usr/bin/docker; \
    rm -rf /tmp/docker; \
    git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter /opt/flutter; \
    git config --system --add safe.directory /opt/flutter; \
    /opt/flutter/bin/flutter --disable-analytics; \
    /opt/flutter/bin/flutter precache --linux; \
    GOPATH=/tmp/gopath GOCACHE=/tmp/gocache go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"; \
    GOPATH=/tmp/gopath GOCACHE=/tmp/gocache go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}"; \
    GOPATH=/tmp/gopath GOCACHE=/tmp/gocache go install "github.com/sqlc-dev/sqlc/cmd/sqlc@${SQLC_VERSION}"; \
    GOPATH=/tmp/gopath GOCACHE=/tmp/gocache go install "github.com/swaggo/swag/cmd/swag@${SWAG_VERSION}"; \
    GOPATH=/tmp/gopath GOCACHE=/tmp/gocache go install "github.com/alphawavesystems/flutter-probe/cmd/probe@${PROBE_VERSION}"; \
    rm -rf /tmp/gopath /tmp/gocache /root/.cache; \
    groupadd --gid 123 docker; \
    useradd --create-home --uid 1001 --gid docker --shell /bin/bash runner; \
    usermod -aG sudo runner; \
    echo "%sudo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/runner; \
    chmod 440 /etc/sudoers.d/runner; \
    curl -fsSL -o /tmp/runner.tar.gz "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${runnerarch}-${RUNNER_VERSION}.tar.gz"; \
    tar -xzf /tmp/runner.tar.gz -C /home/runner; \
    rm /tmp/runner.tar.gz; \
    /home/runner/bin/installdependencies.sh; \
    mkdir -p /home/runner/.pub-cache /home/runner/go /home/runner/.cache; \
    chown -R runner:runner /home/runner /opt/flutter; \
    go version; \
    node --version; \
    flutter --version; \
    docker --version; \
    golangci-lint version; \
    govulncheck -version; \
    sqlc version; \
    swag --version; \
    command -v probe; \
    test -x /home/runner/run.sh'

WORKDIR /home/runner
USER runner
CMD ["/home/runner/run.sh"]
