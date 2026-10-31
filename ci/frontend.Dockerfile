# The x64-quark-frontend / arm-quark-frontend runner. Flutter, Node, the
# Linux desktop packages, and the Actions runner.

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/flutter/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PUB_CACHE=/home/runner/.pub-cache \
    FLUTTER_HOME=/opt/flutter

COPY apt-packages.txt /tmp/apt-packages.txt
COPY common.sh install-frontend.sh /tmp/
ARG TARGETARCH
# Frontend tool versions
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
ARG YQ_VERSION=v4.54.1
ARG RUNNER_VERSION=2.338.2
RUN /tmp/install-frontend.sh && rm -f /tmp/common.sh /tmp/install-frontend.sh

WORKDIR /home/runner
USER runner
CMD ["/home/runner/run.sh"]
