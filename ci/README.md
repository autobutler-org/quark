<!-- cspell:words autobutlerci -->

# CI images

Three Debian stable slim images. `quark/ci-full` is the Errand runner, so a job
with no `container:` runs there. It has Flutter, `linux/apt-packages.txt`, the
Docker client, and the Actions runner. A smaller job names one of the other two:

```yaml
container:
  image: autobutlerci.azurecr.io/quark/ci-backend:latest
```

The tag is `latest`. Jobs do not pin a digest.

| Image | Use |
| --- | --- |
| `quark/ci-full` | Default runner. Flutter, Linux desktop packages, Docker, Actions runner |
| `quark/ci-backend` | Go, Node, Docker, sqlc, swag, golangci-lint, govulncheck |
| `quark/ci-frontend` | Flutter and Node |

The release builds the web app in `ci-frontend`, uploads `internal/server/public`,
and the backend job downloads that directory before GoReleaser. `//go:embed public`
reads it at compile time.

`.github/workflows/ci-image.yml` reads versions from `go.mod`, `pubspec.yaml`,
`.nvmrc`, and the Makefile. It builds all three images for amd64 and arm64.
The workflow runs on every pull request. The builds skip when those files did
not change, and the six build jobs are required checks, so a skip still reports
and a failure does not merge. Push uses `CI_IMAGE_AZURE_CLIENT_ID` and only
runs from `main`.
