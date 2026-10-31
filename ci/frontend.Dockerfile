# The x64-quark-frontend / arm-quark-frontend runner. Flutter, Node, the
# Linux desktop packages, the Docker client, and the Actions runner.

FROM debian:stable-slim

# Debian 13 dropped apt-key, and appimage-builder runs it for key_url.
COPY --from=debian:bookworm-slim /usr/bin/apt-key /usr/bin/apt-key

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PUB_CACHE=/home/runner/.pub-cache \
    FLUTTER_HOME=/opt/flutter \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk

COPY apt-packages.txt /tmp/apt-packages.txt
COPY common.sh install-frontend.sh /tmp/
ARG TARGETARCH
# Frontend tool versions
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
ARG YQ_VERSION=v4.54.1
# Android SDK, no defaults: ci-image.yml passes compileSdk and buildToolsVersion from
# android/app/build.gradle.kts and the command-line tools from the Makefile.
ARG ANDROID_PLATFORM
ARG ANDROID_BUILD_TOOLS_VERSION
ARG ANDROID_CMDLINE_TOOLS_VERSION
ARG DOCKER_VERSION=28.0.4
ARG RUNNER_VERSION=2.338.2
RUN /tmp/install-frontend.sh && rm -f /tmp/common.sh /tmp/install-frontend.sh

WORKDIR /home/runner
USER runner
CMD ["/home/runner/run.sh"]
