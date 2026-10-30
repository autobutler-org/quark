# Job image for the Linux desktop and AppImage builds. Flutter plus
# linux/apt-packages.txt. The workflow copies that list into this
# directory before docker build.

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin \
    PUB_CACHE=/root/.pub-cache \
    FLUTTER_HOME=/opt/flutter

COPY apt-packages.txt /tmp/apt-packages.txt
COPY common.sh install-full.sh /tmp/
ARG TARGETARCH
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
RUN /tmp/install-full.sh && rm -f /tmp/common.sh /tmp/install-full.sh /tmp/apt-packages.txt
