<!-- cspell:words autobutlerci -->

# CI images

Three Ubuntu 22.04 job images, the release the AppImage bundles from. Errand stays on the upstream Actions
runner. A workflow says which image the job runs in:

```yaml
container:
  image: autobutlerci.azurecr.io/quark/ci-backend:latest
```

The tag is `latest`. Jobs do not pin a digest.

| Image | Use |
| --- | --- |
| `quark/ci-backend` | Go, Node, Docker, sqlc, swag, golangci-lint, govulncheck |
| `quark/ci-frontend` | Flutter and Node |
| `quark/ci-full` | Flutter plus `linux/apt-packages.txt` |

The release builds the web app in `ci-frontend`, uploads `internal/server/public`,
and the backend job downloads that directory before GoReleaser. `//go:embed public`
reads it at compile time.

`.github/workflows/ci-image.yml` reads versions from `go.mod`, `pubspec.yaml`,
`.nvmrc`, and the Makefile. It builds all three images for amd64 and arm64.
A pull request that changes those files builds and does not push. Push uses
`CI_IMAGE_AZURE_CLIENT_ID` and only runs from `main`.
