# Job image for Flutter CI. Not the Actions runner. Workflows name this
# image with container:.

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/opt/flutter/bin:/usr/local/bin:/usr/bin:/bin \
    PUB_CACHE=/root/.pub-cache \
    FLUTTER_HOME=/opt/flutter

COPY apt-packages.txt /tmp/apt-packages.txt
COPY common.sh install-frontend.sh /tmp/
ARG TARGETARCH
ARG NODE_VERSION=24.22.2
ARG FLUTTER_VERSION=3.47.8
RUN /tmp/install-frontend.sh && rm -f /tmp/common.sh /tmp/install-frontend.sh
