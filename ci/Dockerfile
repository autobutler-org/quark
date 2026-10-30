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
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        sudo \
        unzip \
        zip \
        xz-utils \
        build-essential \
        python3 \
        python3-venv \
        libglu1-mesa \
        wrk \
    && xargs -a /tmp/apt-packages.txt apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* /tmp/apt-packages.txt

COPY install.sh /tmp/install.sh

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

RUN /tmp/install.sh && rm /tmp/install.sh

WORKDIR /home/runner
USER runner
CMD ["/home/runner/run.sh"]
