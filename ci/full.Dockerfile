# The x64-quark-full / arm-quark-full runner: the backend and frontend images
# together, plus the Actions runner. The workflow copies
# linux/apt-packages.txt into this directory before docker build.

FROM debian:stable-slim

# Debian 13 dropped apt-key, and appimage-builder runs it for key_url.
COPY --from=debian:bookworm-slim /usr/bin/apt-key /usr/bin/apt-key

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/flutter/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PUB_CACHE=/home/runner/.pub-cache \
    FLUTTER_HOME=/opt/flutter \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk

COPY apt-packages.txt /tmp/apt-packages.txt
COPY common.sh install-full.sh /tmp/
ARG TARGETARCH
ARG DOCKER_VERSION
ARG RUNNER_VERSION
# Backend tool versions
ARG GO_VERSION=1.27.3
ARG GOLANGCI_LINT_VERSION=v2.15.0
ARG GOVULNCHECK_VERSION=v1.9.0
ARG SQLC_VERSION=v1.31.1
ARG SWAG_VERSION=v1.16.6
# Frontend tool versions
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
ARG YQ_VERSION
# Android SDK, no defaults: ci-image.yml passes compileSdk and buildToolsVersion from
# android/app/build.gradle.kts and the command-line tools from the Makefile.
ARG ANDROID_PLATFORM
ARG ANDROID_BUILD_TOOLS_VERSION
ARG ANDROID_CMDLINE_TOOLS_VERSION
RUN /tmp/install-full.sh && rm -f /tmp/common.sh /tmp/install-full.sh /tmp/apt-packages.txt

WORKDIR /home/runner
USER runner
CMD ["/home/runner/run.sh"]
