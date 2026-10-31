#!/usr/bin/env bash
# cspell:words TARGETARCH nodearch dockerarch goarch runnerarch installdependencies patchelf GOBIN sdkmanager cmdline
# Shared install steps for the CI job images. The image files pass versions
# as build args, which become environment variables for these scripts.

set -euo pipefail

case "${TARGETARCH}" in
amd64)
	goarch=amd64
	nodearch=x64
	dockerarch=x86_64
	runnerarch=x64
	;;
arm64)
	goarch=arm64
	nodearch=arm64
	dockerarch=aarch64
	runnerarch=arm64
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
		build-essential \
		ca-certificates \
		curl \
		gh \
		git \
		gnupg \
		jq \
		passwd \
		python3 \
		python3-venv \
		sudo \
		unzip \
		xz-utils \
		zip
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

# Google publishes the Android build tools and NDK for x86_64 Linux only, so the
# SDK goes into the amd64 images. The NDK is the version Flutter pins.
install_android() {
	if [ "${TARGETARCH}" != amd64 ]; then
		return
	fi
	install_packages openjdk-21-jdk-headless
	cleanup_packages
	local ndk
	ndk="$(sed -n "s/.*const ndkVersion = '\\([^']*\\)'.*/\\1/p" \
		/opt/flutter/packages/flutter_tools/lib/src/android/gradle_utils.dart)"
	curl -fsSL -o /tmp/cmdline-tools.zip \
		"https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_CMDLINE_TOOLS_VERSION}_latest.zip"
	mkdir -p "${ANDROID_HOME}/cmdline-tools"
	unzip -q /tmp/cmdline-tools.zip -d "${ANDROID_HOME}/cmdline-tools"
	mv "${ANDROID_HOME}/cmdline-tools/cmdline-tools" "${ANDROID_HOME}/cmdline-tools/latest"
	rm /tmp/cmdline-tools.zip
	local sdkmanager="${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager"
	{ yes || true; } | "${sdkmanager}" --licenses >/dev/null
	"${sdkmanager}" --install \
		platform-tools \
		"platforms;android-${ANDROID_PLATFORM}" \
		"build-tools;${ANDROID_BUILD_TOOLS_VERSION}" \
		"ndk;${ndk}"
	/opt/flutter/bin/flutter precache --android
}

# Every image is a runner, and the runner's hooks log in to the registry with
# docker, so the client comes with the runner.
install_runner() {
	install_docker
	docker --version
	groupadd --gid 123 docker
	groupadd --gid 1001 runner
	useradd --create-home --uid 1001 --gid 1001 --groups docker,sudo --shell /bin/bash runner
	echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner
	chmod 440 /etc/sudoers.d/runner
	curl -fsSL -o /tmp/runner.tar.gz \
		"https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${runnerarch}-${RUNNER_VERSION}.tar.gz"
	tar -xzf /tmp/runner.tar.gz -C /home/runner
	rm /tmp/runner.tar.gz
	/home/runner/bin/installdependencies.sh
	mkdir -p /home/runner/.pub-cache /home/runner/go /home/runner/.cache
	chown -R runner:runner /home/runner
	# Gradle installs any SDK component the build asks for and the image lacks.
	for dir in /opt/flutter /opt/android-sdk; do
		if [ -d "${dir}" ]; then
			chown -R runner:runner "${dir}"
		fi
	done
}

install_go_tools() {
	export GOBIN=/usr/local/bin
	export GOPATH=/tmp/gopath
	export GOCACHE=/tmp/gocache
	go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"
	go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}"
	go install "github.com/sqlc-dev/sqlc/cmd/sqlc@${SQLC_VERSION}"
	go install "github.com/swaggo/swag/cmd/swag@${SWAG_VERSION}"
	rm -rf /tmp/gopath /tmp/gocache /root/.cache
}

install_yq() {
	curl -fsSL -o /usr/local/bin/yq \
		"https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${goarch}"
	chmod +x /usr/local/bin/yq
}

# Each component installs its own packages and tools, so the full image is
# install_backend and install_frontend together.
install_backend() {
	install_packages wrk
	cleanup_packages
	install_go
	install_node
	install_go_tools
}

check_backend() {
	command -v go
	go version
	command -v golangci-lint
	golangci-lint version
	command -v govulncheck
	govulncheck -version
	command -v node
	node --version
	command -v sqlc
	sqlc version
	command -v swag
	swag --version
	command -v wrk
}

install_frontend() {
	local linux_packages
	mapfile -t linux_packages < /tmp/apt-packages.txt
	install_packages libglu1-mesa "${linux_packages[@]}"
	cleanup_packages
	install_node
	install_flutter
	install_android
	install_yq
}

check_frontend() {
	command -v cmake
	cmake --version
	command -v flutter
	flutter --version
	command -v node
	node --version
	command -v patchelf
	patchelf --version
	command -v yq
	yq --version
	if [ "${TARGETARCH}" = amd64 ]; then
		java -version
		test -f "${ANDROID_HOME}/platforms/android-${ANDROID_PLATFORM}/android.jar"
	fi
}
