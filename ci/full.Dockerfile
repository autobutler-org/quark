# Default Errand runner image. Flutter, the Linux desktop packages, the
# Docker client, and the Actions runner. The workflow copies
# linux/apt-packages.txt into this directory before docker build.
# Jobs that need a smaller image set container: to ci-backend or ci-frontend.

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin \
    PUB_CACHE=/home/runner/.pub-cache \
    FLUTTER_HOME=/opt/flutter

COPY apt-packages.txt /tmp/apt-packages.txt
COPY common.sh install-full.sh /tmp/
ARG TARGETARCH
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
ARG DOCKER_VERSION=28.0.4
ARG RUNNER_VERSION=2.338.2
RUN /tmp/install-full.sh && rm -f /tmp/common.sh /tmp/install-full.sh /tmp/apt-packages.txt

WORKDIR /home/runner
USER runner
CMD ["/home/runner/run.sh"]
