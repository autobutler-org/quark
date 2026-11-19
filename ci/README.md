<!-- cspell:words autobutlerci -->

# CI images

Three Ubuntu 22.04 images, the release the AppImage bundles from, each with the
Actions runner. Each one is the runner pod for its labels in the `errand` group,
so a job picks its image by label and does not name it with `container:`:

```yaml
runs-on:
  group: errand
  labels: errand-x64-quark-backend
```

The tag is `latest`. Jobs do not pin a digest.

Jobs run on GitHub-hosted runners until the Azure vCPU quota is raised. `AGENTS.md` says how to move them back.

| Image | Labels | Use |
| --- | --- | --- |
| `quark/ci-backend` | `errand-x64-quark-backend`, `errand-arm-quark-backend` | Go, Node, Docker, sqlc, swag, golangci-lint, govulncheck |
| `quark/ci-frontend` | `errand-x64-quark-frontend`, `errand-arm-quark-frontend` | Flutter, Node, Linux desktop packages, Docker |
| `quark/ci-full` | `errand-x64-quark-full`, `errand-arm-quark-full` | `ci-backend` and `ci-frontend` together |

Each label also comes in `small` and `medium` sizes, such as `errand-x64-small-quark-backend`.
`AGENTS.md` says what each size gets and which jobs use it.

The release builds the web app in `ci-frontend`, uploads `internal/server/public`,
and the backend job downloads that directory before GoReleaser. `//go:embed public`
reads it at compile time.

`.github/workflows/ci-image.yml` reads versions from `go.mod`, `pubspec.yaml`,
`.nvmrc`, and the Makefile. It builds all three images for amd64 and arm64.
The workflow runs on every pull request. The builds skip when those files did
not change, and the `ci-image` job is the required check, so a skip still
passes and a failure does not merge. Push uses `CI_IMAGE_AZURE_CLIENT_ID` and only
runs from `main`.

## The factory worker

`factory-worker.Dockerfile` is not a runner. It is the image the
[factory](https://github.com/autobutler-org/factory) runs quark's agent sessions
and gate in: `ghcr.io/autobutler-org/factory-worker` plus Flutter at the
`pubspec.yaml` version and the Go tools at the Makefile's pins, installed by the
same `common.sh` functions as the images above. `make build/docker/factory-worker`
builds it for this machine. `ci-image.yml` builds it for amd64 and arm64 on a pull
request that touches it, `common.sh`, `pubspec.yaml` or the Makefile, and on
`main` publishes `ghcr.io/autobutler-org/quark-factory-worker` tagged
`<Flutter version>-<short sha>` and `latest`. `AGENTS.md` (The factory) says how to
move quark onto a new tag.
