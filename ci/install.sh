#!/usr/bin/env bash
# cspell:words TARGETARCH nodearch dockerarch runnerarch installdependencies
# Install the CI toolchain and the Actions runner. Versions and TARGETARCH
# come from the image build. The Dockerfile is what runs this.

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

curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${goarch}.tar.gz" | tar -C /usr/local -xz
curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${nodearch}.tar.xz" \
	| tar -C /usr/local --strip-components=1 -xJ
curl -fsSL "https://download.docker.com/linux/static/stable/${dockerarch}/docker-${DOCKER_VERSION}.tgz" \
	| tar -xz -C /tmp
install -m 755 /tmp/docker/docker /usr/bin/docker
rm -rf /tmp/docker

git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter /opt/flutter
git config --system --add safe.directory /opt/flutter
/opt/flutter/bin/flutter --disable-analytics
/opt/flutter/bin/flutter precache --linux

export GOPATH=/tmp/gopath
export GOCACHE=/tmp/gocache
go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"
go install "golang.org/x/vuln/cmd/govulncheck@${GOVULNCHECK_VERSION}"
go install "github.com/sqlc-dev/sqlc/cmd/sqlc@${SQLC_VERSION}"
go install "github.com/swaggo/swag/cmd/swag@${SWAG_VERSION}"
go install "github.com/alphawavesystems/flutter-probe/cmd/probe@${PROBE_VERSION}"
rm -rf /tmp/gopath /tmp/gocache /root/.cache

groupadd --gid 123 docker
useradd --create-home --uid 1001 --gid docker --shell /bin/bash runner
usermod -aG sudo runner
echo '%sudo ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/runner
chmod 440 /etc/sudoers.d/runner

curl -fsSL -o /tmp/runner.tar.gz \
	"https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${runnerarch}-${RUNNER_VERSION}.tar.gz"
tar -xzf /tmp/runner.tar.gz -C /home/runner
rm /tmp/runner.tar.gz
/home/runner/bin/installdependencies.sh
mkdir -p /home/runner/.pub-cache /home/runner/go /home/runner/.cache
chown -R runner:runner /home/runner /opt/flutter

go version
node --version
flutter --version
docker --version
golangci-lint version
govulncheck -version
sqlc version
swag --version
command -v probe
test -x /home/runner/run.sh
