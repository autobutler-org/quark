# Default Errand runner image. Flutter, the Linux desktop packages, the
# Docker client, and the Actions runner. The workflow copies
# linux/apt-packages.txt into this directory before docker build.
# Jobs that need a smaller image set container: to ci-backend or ci-frontend.

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PUB_CACHE=/home/runner/.pub-cache \
    FLUTTER_HOME=/opt/flutter

COPY apt-packages.txt /tmp/apt-packages.txt
COPY common.sh install-full.sh /tmp/
ARG TARGETARCH
ARG DOCKER_VERSION=28.0.4
ARG RUNNER_VERSION=2.338.2
# Backend tool versions
ARG GO_VERSION=1.27.3
ARG GOLANGCI_LINT_VERSION=v2.15.0
ARG GOVULNCHECK_VERSION=v1.9.0
ARG SQLC_VERSION=v1.31.1
ARG SWAG_VERSION=v1.16.6
# Frontend tool versions
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
RUN /tmp/install-full.sh && rm -f /tmp/common.sh /tmp/install-full.sh /tmp/apt-packages.txt

WORKDIR /home/runner
USER runner
CMD ["/home/runner/run.sh"]
