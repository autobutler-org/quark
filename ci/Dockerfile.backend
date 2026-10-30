# cspell:words GOBIN
# Job image for Go CI. Not the Actions runner. Workflows name this image
# with container:.

FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PATH=/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin \
    GOBIN=/usr/local/bin

COPY common.sh install-backend.sh /tmp/
ARG TARGETARCH
ARG GO_VERSION=1.27.3
ARG NODE_VERSION=24.22.2
ARG DOCKER_VERSION=28.0.4
ARG GOLANGCI_LINT_VERSION=v2.15.0
ARG GOVULNCHECK_VERSION=v1.9.0
ARG SQLC_VERSION=v1.31.1
ARG SWAG_VERSION=v1.16.6
RUN /tmp/install-backend.sh && rm -f /tmp/common.sh /tmp/install-backend.sh
