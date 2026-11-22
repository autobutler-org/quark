# cspell:words TARGETARCH
# Quark's factory worker: the factory's dev container plus Flutter and the Go tools
# quark's checks run. The factory (autobutler-org/factory) runs it as uid 1000 under
# Pod Security "restricted" on linux/arm64 nodes, and runs the gate in
# .factory/config.toml with only PATH, the locale and a scratch HOME, so every tool
# here works with nothing else set. Flutter stays out of the shared base image.

# Renovate's Dockerfile manager moves this tag. Keep the base's entrypoint.
FROM ghcr.io/autobutler-org/factory-worker:v0.1.4

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root

COPY common.sh /tmp/
ARG TARGETARCH
# No defaults: `make build/docker/factory-worker`, which ci-image.yml runs, passes
# them from pubspec.yaml and the Makefile.
ARG FLUTTER_VERSION
ARG GOLANGCI_LINT_VERSION
ARG GOVULNCHECK_VERSION
ARG SQLC_VERSION
ARG SWAG_VERSION
# The same Flutter clone and go install lines as the CI images. Flutter unpacks
# its Dart SDK and engine artifacts with unzip and xz, which the base lacks.
# Native assets build hooks (pdfium_dart's) compile C with native_toolchain_c,
# which on Linux takes only clang, the package linux/apt-packages.txt gives
# the CI images; the base's gcc does not count. Flutter
# writes to its own cache at run time, so uid 1000 owns it. HOME is root's here,
# so nothing root writes lands in the factory user's home.
RUN export HOME=/root \
    && source /tmp/common.sh \
    && install_packages clang unzip xz-utils zip \
    && cleanup_packages \
    && install_flutter \
    && install_go_tools \
    && chown -R 1000:1000 /opt/flutter \
    && rm -rf /tmp/common.sh /root/.config /root/.dart-tool /root/.flutter

ENV PATH=/opt/flutter/bin:${PATH}
USER 1000:1000

# Analytics off and first-run notices done for the agent's HOME. The gate's
# scratch HOME starts empty, so .factory/config.toml repeats this there.
RUN flutter --disable-analytics \
    && dart --disable-analytics \
    && flutter config --no-cli-animations \
    && clang --version \
    && flutter --version \
    && dart --version \
    && golangci-lint version \
    && govulncheck -version \
    && sqlc version \
    && swag --version
