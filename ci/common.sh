# cspell:words TARGETARCH nodearch dockerarch goarch
# Shared install steps for the CI job images. The Dockerfiles pass versions
# as build args, which become environment variables for these scripts.

set -euo pipefail

case "${TARGETARCH}" in
amd64)
	goarch=amd64
	nodearch=x64
	dockerarch=x86_64
	;;
arm64)
	goarch=arm64
	nodearch=arm64
	dockerarch=aarch64
	;;
*)
	echo "unsupported architecture ${TARGETARCH}" >&2
	exit 1
	;;
esac

install_packages() {
	apt-get update
	apt-get install -y --no-install-recommends "$@"
}

cleanup_packages() {
	rm -rf /var/lib/apt/lists/*
}

base_packages() {
	install_packages \
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
		"$@"
	cleanup_packages
}

install_go() {
	curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${goarch}.tar.gz" | tar -C /usr/local -xz
}

install_node() {
	curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${nodearch}.tar.xz" \
		| tar -C /usr/local --strip-components=1 -xJ
}

install_docker() {
	curl -fsSL "https://download.docker.com/linux/static/stable/${dockerarch}/docker-${DOCKER_VERSION}.tgz" \
		| tar -xz -C /tmp
	install -m 755 /tmp/docker/docker /usr/bin/docker
	rm -rf /tmp/docker
}

install_flutter() {
	git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter /opt/flutter
	git config --system --add safe.directory /opt/flutter
	/opt/flutter/bin/flutter --disable-analytics
	/opt/flutter/bin/flutter precache --linux
}

install_go_tools() {
	export GOPATH=/tmp/gopath
	export GOCACHE=/tmp/gocache
	go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"
	go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}"
	go install "github.com/sqlc-dev/sqlc/cmd/sqlc@${SQLC_VERSION}"
	go install "github.com/swaggo/swag/cmd/swag@${SWAG_VERSION}"
	rm -rf /tmp/gopath /tmp/gocache /root/.cache
}
