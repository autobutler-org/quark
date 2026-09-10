# Quark

Your own private cloud, running in your house. Photos, files, documents — all on hardware you own, off servers you don't trust.

[![CI - Android](https://github.com/autobutler-org/quark/actions/workflows/ci-android.yml/badge.svg?branch=main)](https://github.com/autobutler-org/quark/actions/workflows/ci-android.yml)
[![CI - Backend](https://github.com/autobutler-org/quark/actions/workflows/ci-backend.yml/badge.svg?branch=main)](https://github.com/autobutler-org/quark/actions/workflows/ci-backend.yml)
[![CI - iOS](https://github.com/autobutler-org/quark/actions/workflows/ci-ios.yml/badge.svg?branch=main)](https://github.com/autobutler-org/quark/actions/workflows/ci-ios.yml)
[![CI - Web](https://github.com/autobutler-org/quark/actions/workflows/ci-web.yml/badge.svg?branch=main)](https://github.com/autobutler-org/quark/actions/workflows/ci-web.yml)
[![Code Quality](https://github.com/autobutler-org/quark/actions/workflows/check.yml/badge.svg)](https://github.com/autobutler-org/quark/actions/workflows/check.yml)
[![CodeQL](https://github.com/autobutler-org/quark/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/autobutler-org/quark/actions/workflows/codeql.yml)
[![License: MIT-0](https://img.shields.io/badge/License-MIT--0-yellow.svg)](LICENSE)

---

## What is it?

Quark is a self-hosted personal cloud that runs on a device in your home. Think Google Drive or iCloud, except the data never leaves your house and nobody's training AI on your family photos.

You buy the hardware once. No subscriptions. No data mining. It's yours.

## Stack

- **Go** + Gin — backend server
- **Flutter** — cross-platform frontend (web, iOS, Android)
- **SQLite** — embedded local database
- **OpenTelemetry** — observability

## Getting started

**Prerequisites:** Go, Flutter, Make, [air](https://github.com/air-verse/air), sqlc, swag

```bash
git clone https://github.com/autobutler-org/quark.git # Include --recursive if you want to do OS image builds
cd quark
make setup
make generate
make build
```

### Run it locally

Backend with hot reload. Pick a mode — they differ in scheme *and* port:

```bash
make watch/backend         # plain HTTP  on http://localhost:8080
make watch/backend/secure  # HTTPS       on https://localhost (:443), self-signed cert
```

The secure mode generates a self-signed certificate on first boot. It is not
added to any trust store, so `curl` needs `-k` and browsers will warn; the
Flutter app skips chain verification for local addresses on purpose. Binding
`:443` requires root on Linux — see `AS_ROOT=1` below.

Without hot reload, `make serve/backend` and `make serve/backend/secure` are the
same two modes.

Frontend (web):

```bash
make serve/frontend
```

Frontend (mobile emulator):

```bash
make emulate          # default platform
make emulate/android  # or emulate/ios
make serve/frontend/mobile
```

#### Container

Runs a **published release**, not your working tree:

```bash
make build/docker                       # build the image for the latest released tag
make serve/docker                       # run it on http://localhost:8080
make serve/docker DOCKER_PORT=9000      # different host port
make serve/docker DOCKER_DATA=/abs/path # use a Quark directory on the host
make clean/docker                       # remove the container
```

It downloads the tarball for a tagged version, so it will not pick up local
changes — `make watch/backend` is still the development loop. Use this to check
the shipped artifact, to reproduce something a user reports on a specific
version, or to try Quark without a Go and Flutter toolchain.

State lives in the `quark-data` volume by default and persists between runs.
See [docs/container.md](docs/container.md) for Kubernetes, the uid 999 the data
directory must be owned by on Linux, and the rest.

> USB device mounting requires root on Linux, as does binding `:443` in secure
> mode. Use `AS_ROOT=1` with any backend target if you need it — e.g.
> `make watch/backend/secure AS_ROOT=1`.

Swagger UI is at `http://localhost:8080/swagger` in insecure mode, or
`https://localhost/swagger` in secure mode.

### Other useful commands

```bash
make check    # lint
make format   # format
make help     # all targets
```

## Docs

- [Dev Onboarding](docs/dev-onboarding.md)
- [Authentication](docs/auth.md)
- [Mobile Setup](docs/mobile-setup.md)
- [Raspberry Pi Setup](os/README.md)
- [Release Process](docs/release.md)
- [Contributing](CONTRIBUTING.md)

## Contributing

We use linear commit history — one focused commit per PR is the norm. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full rundown.

## License

MIT No Attribution (MIT-0). See [LICENSE](LICENSE).
