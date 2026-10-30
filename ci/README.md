<!-- cspell:words autobutlerci -->

# CI image

Debian stable slim, with Go, Flutter, Node, and the CI tools pinned in this
repo. Errand runs it as the runner image. The tag is `latest`. Each new job
pod sets `imagePullPolicy: Always`, so the job gets whatever main last pushed.
Jobs do not pin a digest.

The image is `autobutlerci.azurecr.io/quark/ci`. The workflow is
`.github/workflows/ci-image.yml`. It reads versions from `go.mod`,
`pubspec.yaml`, `.nvmrc`, and the `*_VERSION` lines in the Makefile, and it
copies `linux/apt-packages.txt` into this directory before `docker build`.

Push uses a user-assigned identity that can write this registry and nothing
else. The workflow reads its client id from the repository variable
`CI_IMAGE_AZURE_CLIENT_ID`. After the iac apply:

```
gh variable set CI_IMAGE_AZURE_CLIENT_ID --repo autobutler-org/quark --body <ci_image_identity_client_id>
```

The identity's federated subject is Quark's immutable OIDC prefix on `main`.
A pull request build cannot push.
