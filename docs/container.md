# Running Quark in a Container

Every release publishes a multi-architecture image to GHCR:

```text
ghcr.io/autobutler-org/quark:0.36.2
ghcr.io/autobutler-org/quark:latest
```

It carries a released binary and its runtime dependencies — no Go toolchain and no source.
`linux/amd64` and `linux/arm64` are both in the manifest, so the same tag runs on a cloud VM and on
a Raspberry Pi.

The image carries no `ffmpeg` (#2382). A video's thumbnail is a keyframe decoded in pure Go, for
AV1 and VP8, and one a client renders for every other codec; probing, trimming, and converting
video copy streams in pure Go. A RAW photo's preview comes from `dcraw`, then `exiftool`, and
nothing else. With `ffmpeg` and Debian's full codec set the image was around 600 MB, most of it
that package; the size without it has not been measured yet.

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
docker run -d --name quark --restart unless-stopped -p 8080:8080 \
  -v quark-data:/var/lib/quark ghcr.io/autobutler-org/quark:latest
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

Use it to check a change under the shipped runtime — same base image, same RAW tools, same `quark`
user, same mount layout — or to test arm64 from an amd64 machine and the other way round. It is not
a development loop; `make watch/backend` still is.

`GOARCH` has to match the platform Docker runs the image as (`arm64` on Apple Silicon, `amd64`
otherwise), or the binary will not exec. The mount is `:ro` on purpose: nothing in the container has
any business writing to its own executable.

The web frontend is `//go:embed`ed into the binary, so the UI you get is whatever was in
`internal/server/public/` at build time — run `make build/frontend/web` first, or a stale UI ships
with your fresh backend.

This is a released image running an unreleased binary. If your working tree carries a migration the
release does not, it runs against whatever is in the mounted volume and does not roll back. A binary
without that migration then refuses to start on the volume: the container exits, and its log names the
database file and what to do with it.

## Updating

Two ways, and they mix:

- **Settings → Updates.** Quark downloads the release, checks its checksum, writes the binary to
  `/var/lib/quark/bin/quark` in the volume, and exits. `quark serve` checks that directory on every
  start and runs the binary there when it reports a newer version than the one in the image. The
  update survives the container being recreated, because it lives in the volume.
- **A new image.** `docker pull` and recreate the container. An image newer than the last update
  from Settings runs its own binary, and the older copy in the volume is ignored.

`QUARK_UPDATE_DIR` names the directory, and the image sets it. The image's own binary in
`/usr/local/bin` belongs to root, and anything written into the container's layer would vanish on
the next `docker run`. A copy there would also leave the image's older binary running against a
database the update had already migrated.

Quark exits to finish an update, so something has to start it again. Run the container with
`--restart unless-stopped` (or `always`). A Kubernetes Deployment restarts it on its own.
`make serve/docker` runs with `--rm`, so after an update the container is gone, and the next
`make serve/docker` starts the updated binary from the volume.

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
          env:
            # Every request arrives from the ingress controller, so Quark has to
            # believe its X-Forwarded-For to rate-limit logins per client rather
            # than per ingress pod. Set this to the CIDR your ingress pods run
            # in (often the cluster's pod CIDR), and keep loopback for remote
            # access; see "Behind a proxy" below.
            - name: QUARK_TRUSTED_PROXIES
              value: "10.244.0.0/16,127.0.0.1,::1"
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
matter of raising `replicas`, and pointing it at [PostgreSQL](#postgresql) does not change that.

## PostgreSQL

Quark keeps its database in a SQLite file under the data directory unless it is told otherwise. To use a
PostgreSQL server instead, give the container two environment variables and an empty database:

```bash
docker run -d --name quark --restart unless-stopped -p 8080:8080 \
  -e QUARK_DB_BACKEND=postgres \
  -e QUARK_DATABASE_URL='postgres://quark:password@db.example:5432/quark?sslmode=require' \
  -v quark-data:/var/lib/quark ghcr.io/autobutler-org/quark:latest
```

In Kubernetes, put the URL in a `Secret` and reference it from the Deployment's `env`. It carries the password.

- **The database starts empty.** Quark creates its schema on first start and brings it up to date on every
  later one. It will not start on a database that already has tables it did not make: give it a database of its
  own, or a schema of its own with `?search_path=<schema>` on the URL.
- **Quark never resets or repairs a PostgreSQL database.** If it cannot connect, or finds a schema it cannot
  carry forward, it exits with a message saying what it found and what to do.
- **The volume is still needed.** Uploaded files, the tailnet identity, the TLS certificate and an update
  installed from Settings all live under `/var/lib/quark` whatever the database is.
- **One replica is still the rule**, and `strategy: Recreate` with it. PostgreSQL removes the database's reason
  for that and none of the others: the file store on a `ReadWriteOnce` volume, the event bus, running jobs and
  the tailnet identity each belong to one process. Running several instances is #2964.
- **Not everything works yet.** Content search answers `501` with the issue that tracks it;
  [the full list](architecture/data.md#what-does-not-work-on-postgresql-yet) is in the data architecture page.
  To move an existing SQLite install's data across, run `quark move-to-postgres` against the same volume
  with the server stopped: [Moving to PostgreSQL](architecture/postgres-move.md).

### Requirements

- **PostgreSQL 14 or newer.** CI tests 18. An older server is refused at startup with the version it found.
- **No extension today.** Filename search on PostgreSQL (#2958) will need `pg_trgm`, which its migration
  enables; the role will then need permission to create it, or an admin creates it first.
- **`fsync` and `synchronous_commit` not `off`.** Quark refuses to start on either, because a crash could then
  lose or corrupt what it already acknowledged. [Durability](architecture/durability.md#postgresql) has the
  rest, and what stays the operator's to get right.

### Connection settings

`QUARK_DATABASE_URL` is a PostgreSQL connection URL, `postgres://<user>:<password>@<host>:<port>/<database>?<options>`.

- `sslmode=require` (or `verify-full`) for a server across a network; `sslmode=disable` only on a private link.
- `search_path=<schema>` to give Quark a schema of its own in a shared database.
- The pool opens up to 16 connections, gives one back after 5 idle minutes, and retires every connection after
  30, so a failover or a moved DNS name is picked up without a restart. Leave room for it under the server's
  `max_connections`.
- The session time zone is pinned to UTC whatever the server or role default is.

### Backup and restore

On PostgreSQL the database is backed up with PostgreSQL's tools, and Quark's snapshot backup covers the files
only: a snapshot there writes no `chat_backup.db` or `vault_items_backup.db`, and removes the ones an earlier SQLite
snapshot left at the drive's root, because the chat and the vault are
in the database ([Backup](architecture/backup.md#on-postgresql)).

To back up:

1. Dump the database, or rely on the managed service's backups:

   ```bash
   pg_dump --format=custom --file=quark.dump "$QUARK_DATABASE_URL"
   ```

   `pg_dump` and `pg_restore` do not accept `search_path` in a URL. If Quark's URL carries one, give them the
   URL without it and name the schema with `--schema=<schema>`.

2. Back up the files: a snapshot backup onto a drive with the `snapshot-backup` role, or a copy of the
   `/var/lib/quark` volume.

The dump and the files are taken at different moments, as the database and the files are on SQLite.

To restore:

1. Stop Quark.
2. Create an empty database and load the dump into it:

   ```bash
   pg_restore --no-owner --dbname="$QUARK_DATABASE_URL" quark.dump
   ```

3. Put the files back under the volume's `data/files/` directory. From a snapshot, that is the contents of
   its `internal/` directory; each other drive's files are in its `<device>_<serial>/` directory.
4. Start Quark. It finds `schema_migrations` and carries the schema forward. A dump from a newer build than
   the image refuses to start, saying so.

A backup does not restore across backends: a dump restores onto PostgreSQL only, and a SQLite install's
`chat_backup.db` and `vault_items_backup.db` onto SQLite only. Moving a SQLite install to PostgreSQL is
`quark move-to-postgres` ([Moving to PostgreSQL](architecture/postgres-move.md)).

## The data directory

The mount point is `/var/lib/quark`, the whole Quark root rather than just the `data/` inside it.
Two things live under it: `data/` (the SQLite database and every uploaded file) and `tsnet/`, where
[`remoteutil.stateDir()`](../pkg/util/remoteutil/helpers.go) keeps tailnet enrollment. `tsnet/` is a
sibling of `data/`, so mounting only `data/` would throw away the tailnet identity every time the
container was recreated. An update installed from Settings adds `bin/` (see Updating above). The root is also the `quark` user's home directory, so a stray `.cache/`
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
whatever binary version the image carries, and migrations run on start and do not roll back. An image
older than the database it is pointed at exits without touching it, and says so in its log.

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

## USB drives

Mounting a USB drive from the Devices page needs a privileged container:

```bash
docker run -d --name quark --restart unless-stopped --privileged \
  -p 8080:8080 -v quark-data:/var/lib/quark ghcr.io/autobutler-org/quark:latest
```

Quark mounts a drive the way it does on a device, with `sudo mount` onto
`/var/lib/quark/data/mounts/<serial>`. The image carries `sudo` and the same one-line sudoers rule
`quark install` writes, which allows `mount` and `umount` under that directory and nothing else.
Without `--privileged` the container has no `CAP_SYS_ADMIN` and no `/dev/sdX` nodes, so the mount
fails with `permission denied`. Everything else in Quark works without it.

`--privileged` gives the container root's power over the host's devices, so the container stops
isolating Quark from the machine it runs on. Leave it off if you do not need USB drives.

The `quark` user is in the image's `disk` group (gid 6), so `blkid` can read a drive's filesystem
type and an exFAT or NTFS drive is mounted writable by Quark. Debian and Ubuntu hosts own `/dev/sd*`
as gid 6 too. On a host where `disk` has a different gid, add it with `--group-add <gid>`.

Docker copies `/dev` when the container starts, so a drive plugged in afterwards does not appear
until `docker restart quark`. A mount lives in the container's own mount namespace: the host does
not see it, and a restart drops it until Quark mounts the drive again.

## TLS

The image sets `QUARK_INSECURE=true`, so it serves plain HTTP on `$PORT` (8080). This is the right
default for a container: in a cluster TLS terminates at the ingress, and on a cloud runtime it
terminates at the load balancer, so a self-signed certificate inside the pod is something to work
around rather than a protection.

Do not expose port 8080 directly to the internet. To use Quark's own self-signed certificate
instead, unset `QUARK_INSECURE` and set `HTTPS_PORT`.

## Behind a proxy

Quark rate-limits login, setup and account recovery per client IP. It takes that IP
from `X-Forwarded-For`, and whether the connection was HTTPS from `X-Forwarded-Proto`, only when the
direct peer is a trusted proxy. Anyone else could put any address in those headers.

`QUARK_TRUSTED_PROXIES` is a comma-separated list of IPs and CIDRs, such as
`10.244.0.0/16,192.168.1.10`. Unset, it is `127.0.0.1,::1`: the remote-access proxy runs inside the
quark and connects over loopback. Setting it replaces that default rather than adding to it, so
keep `127.0.0.1,::1` in the list if the quark uses remote access. An entry that is neither an IP nor
a CIDR stops `quark serve` at startup with an error naming it.

Behind an ingress controller or a load balancer that connects from inside your network, set it to
that proxy's address range. Left unset, every client looks like the proxy, they all share one
rate-limit bucket, and one client guessing passwords locks everyone else out of login. Do not set it
wider than the proxy: a peer inside the range can claim any client IP.
