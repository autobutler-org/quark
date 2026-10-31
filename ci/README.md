<!-- cspell:words autobutlerci -->

# CI images

Three Ubuntu 22.04 images, the release the AppImage bundles from, each with the
Actions runner. Each one is the runner pod for its labels in the `errand` group,
so a job picks its image by label and does not name it with `container:`:

```yaml
runs-on:
  group: errand
  labels: x64-quark-backend
```

The tag is `latest`. Jobs do not pin a digest.

| Image | Labels | Use |
| --- | --- | --- |
| `quark/ci-backend` | `x64-quark-backend`, `arm-quark-backend` | Go, Node, Docker, sqlc, swag, golangci-lint, govulncheck |
| `quark/ci-frontend` | `x64-quark-frontend`, `arm-quark-frontend` | Flutter, Node, Linux desktop packages, Docker |
| `quark/ci-full` | `x64-quark-full`, `arm-quark-full` | `ci-backend` and `ci-frontend` together |

The release builds the web app in `ci-frontend`, uploads `internal/server/public`,
and the backend job downloads that directory before GoReleaser. `//go:embed public`
reads it at compile time.

`.github/workflows/ci-image.yml` reads versions from `go.mod`, `pubspec.yaml`,
`.nvmrc`, and the Makefile. It builds all three images for amd64 and arm64.
The workflow runs on every pull request. The builds skip when those files did
not change, and the `ci-image` job is the required check, so a skip still
passes and a failure does not merge. Push uses `CI_IMAGE_AZURE_CLIENT_ID` and only
runs from `main`.
