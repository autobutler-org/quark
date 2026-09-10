# Running Quark in a Container

Every release publishes a multi-architecture image to GHCR:

```text
ghcr.io/autobutler-org/quark:0.36.2
ghcr.io/autobutler-org/quark:latest
```

It carries a released binary and its runtime dependencies — no Go toolchain and no source.
`linux/amd64` and `linux/arm64` are both in the manifest, so the same tag runs on a cloud VM and on
a Raspberry Pi.

The image is around 600 MB, and most of that is `ffmpeg`. Quark shells out to `ffmpeg` and
`ffprobe` for video thumbnails and transcoding, so they have to be on `PATH`; Debian's `ffmpeg`
package pulls in the full codec set. A deployment that never touches video still carries it. If it
were ever left out, Quark would still start and serve: `videoutil.Available()` gates every caller,
so `POST /api/v0/videos/trim` answers `501 Not Implemented` and thumbnail generation returns an
error for video files, while everything else works normally.

To build it yourself for the host architecture, `make build/docker`. It packages the most recent
git tag; pass `BUILD_NAME=X.Y.Z` for a different released version. The image cannot be built for a
version that was never released — there is no build stage, only a download of that release's assets.

## Locally

From a checkout of this repository:

```bash
make serve/docker
```

That runs the most recent tagged version on <http://localhost:8080>, keeping its state in a named
`quark-data` volume so the account you create on first launch survives a restart. Ctrl-C stops it;
`make clean/docker` clears a container left behind by a crashed run, and leaves the volume alone.
Override with `DOCKER_PORT=`, `BUILD_NAME=`, `DOCKER_IMAGE=` or `DOCKER_VOLUME=`; `docker volume rm
quark-data` starts over. Port 8080 is the one `make serve/backend` uses too, so pass
`DOCKER_PORT=9000` to run both at once. Without a checkout, the same thing by hand:

```bash
docker run -p 8080:8080 -v quark-data:/var/lib/quark ghcr.io/autobutler-org/quark:latest
```

Everything Quark keeps — the SQLite database and every uploaded
file — lives under the mounted volume, so the container itself stays disposable.

The entrypoint is `quark` with a default command of `serve`, so any other subcommand is reachable
the usual way:

```bash
docker run --rm ghcr.io/autobutler-org/quark:latest version
```

## Running your own build

The image compiles nothing, but it will run a working-tree binary bind-mounted over the one it
ships:

```bash
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -o build/quark-linux ./cmd/quark/main.go
docker run --rm -v "$PWD/build/quark-linux:/usr/local/bin/quark:ro" \
  ghcr.io/autobutler-org/quark:0.36.2 version
# NOCOMMIT
```

Use it to check a change under the shipped runtime — same base image, same ffmpeg, same `quark`
user, same mount layout — or to test arm64 from an amd64 machine and the other way round. It is not
a development loop; `make watch/backend` still is.

`GOARCH` has to match the platform Docker runs the image as (`arm64` on Apple Silicon, `amd64`
otherwise), or the binary will not exec. The mount is `:ro` on purpose: nothing in the container has
any business writing to its own executable.

The web frontend is `//go:embed`ed into the binary, so the UI you get is whatever was in
`internal/server/public/` at build time — run `make build/frontend/web` first, or a stale UI ships
with your fresh backend.

This is a released image running an unreleased binary. If your working tree carries a migration the
release does not, it runs against whatever is in the mounted volume and does not roll back.

## Kubernetes

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: quark-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 100Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: quark
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: quark
  template:
    metadata:
      labels:
        app: quark
    spec:
      containers:
        - name: quark
          image: ghcr.io/autobutler-org/quark:latest
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: data
              mountPath: /var/lib/quark
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: quark-data
---
apiVersion: v1
kind: Service
metadata:
  name: quark
spec:
  selector:
    app: quark
  ports:
    - port: 80
      targetPort: 8080
```

One replica and `strategy: Recreate`, both deliberate: the state is one SQLite database on one
`ReadWriteOnce` volume, and a second writer would corrupt it. Scaling Quark horizontally is not a
matter of raising `replicas`.

## The data directory

The mount point is `/var/lib/quark`, the whole Quark root rather than just the `data/` inside it.
Two things live under it: `data/` (the SQLite database and every uploaded file) and `tsnet/`, where
[`remoteutil.stateDir()`](../pkg/util/remoteutil/helpers.go) keeps tailnet enrollment. `tsnet/` is a
sibling of `data/`, so mounting only `data/` would throw away the tailnet identity every time the
container was recreated. The root is also the `quark` user's home directory, so a stray `.cache/`
may appear beside them.

Pointing it at a directory on the host instead of a named volume:

```bash
make serve/docker DOCKER_DATA=/absolute/path/to/quark
```

The path must be absolute and must already exist. A relative one is not an error to Docker — it
quietly creates a named volume rather than mounting the directory, and Quark comes up empty with
nothing on screen to explain why — so the target rejects it up front.

An empty directory is fine; the server creates `data/` inside it on first boot. Pointing it at an
**existing** Quark directory means the container reads and writes your real photos and database with
whatever binary version the image carries, and migrations run on start and do not roll back.

### Why the user is named `quark`

The name is load-bearing. `storageutil.GetDataDir()`
([`pkg/util/storageutil/dir.go`](../pkg/util/storageutil/dir.go)) resolves to `/var/lib/quark/data`
only when the process user is literally `quark`; under any other name it falls back to
`$HOME/quark/data`. Overriding the user — a `runAsUser` in a pod security context, `docker run -u` —
moves the state somewhere the mount is not, and the instance comes up empty on every restart.

That is also why the fix for a permission error is never `--user $(id -u)`. The container runs as
uid 999, and on Linux that uid is enforced against the host's ownership, so a bind-mounted directory
owned by your own user gives `EACCES`. Chown the directory instead:

```bash
sudo chown -R 999:999 /absolute/path/to/quark
```

On Docker Desktop for macOS this does not come up — virtiofs maps ownership, so the writes just
work.

## TLS

The image sets `QUARK_INSECURE=true`, so it serves plain HTTP on `$PORT` (8080). This is the right
default for a container: in a cluster TLS terminates at the ingress, and on a cloud runtime it
terminates at the load balancer, so a self-signed certificate inside the pod is something to work
around rather than a protection.

Do not expose port 8080 directly to the internet. To use Quark's own self-signed certificate
instead, unset `QUARK_INSECURE` and set `HTTPS_PORT`.
