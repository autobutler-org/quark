# Multi-instance harness

Several Quark instances on one PostgreSQL and one shared files directory, behind a load balancer with no
affinity (#2971). It is where each sub-issue of epic #2964 proves its "done when", and CI runs it on every
backend change, so a change that brings back per-process state breaking a case fails.

## How it runs

Each test starts its own cluster: an empty PostgreSQL schema (`dbtest.PostgresURL`), a shared files directory,
and instances of `QUARK_BINARY` started one after another. Every instance has a `HOME` of its own, so its data
directory, `tmp`, certificates and logs are its own, and its files directory is a symlink to the shared one.
The access checks resolve the files root through its symlinks, so the link stands in for a network mount.

The balancer is an `httputil.ReverseProxy` in the test, round-robin over the instances that answered their
last health check (`/api/v0/auth/status`, four times a second), the way a cloud load balancer behaves.
Websockets pass through it. Most cases address the instances directly instead, so "made on one, used on the
other" never depends on where the balancer happened to send a request.

These are host processes, not containers: the release image downloads a published release and cannot run the
build under test, and processes need no Docker.

## Cases

| Test | Done when of | State |
| --- | --- | --- |
| `TestSessionsAreShared` | sessions (audit, "Confirmed safe") | passes |
| `TestSharedFileWrites` | #2968: no lost writes, partial reads or staging files left | passes |
| `TestJobOwnership` | #2966: a late instance leaves a job alone; a killed owner's job is finished by another | passes |
| `TestEventsCrossInstances` | #2965: an upload is live on the other instance's socket; a share works on both | known broken |
| `TestChunkedUploadSplitAcrossInstances` | #2967: a chunked upload spread over both | known broken |
| `TestDownloadTokenAcrossInstances` | #2967: a download token issued by one, used on the other | known broken |
| `TestLoginLockoutAcrossInstances` | #2967: lockout after as many failures as on one instance | known broken |
| `TestRollingUpgrade` | #2970: previous release to this build, one instance at a time, under load | known broken |
| `TestBalancerSpreadsRequests` | the harness: the balancer reaches every instance | passes |

A known-broken case calls `knownBroken(t, <issue>, err)`. While the case fails it skips, naming the issue;
once it passes it fails and says to remove the marker. The pull request that fixes a case therefore removes its
marker, and from then on the case guards the fix.

`TestJobOwnership` kills the instance that queued a music rescan whenever the kill lands: before the claim
another instance takes the job, during the run it waits out the 60 s lease, and after it there is nothing left
to do. It does not force the middle one.

## Run

```bash
make serve/postgres
make test/multiinstance
```

| Variable | Purpose |
| --- | --- |
| `QUARK_BINARY` | The build under test (the Makefile passes `build/quark`) |
| `QUARK_PREVIOUS_BINARY` | The release the rolling upgrade starts from. Unset, that case skips; CI downloads the latest release |
| `QUARK_DB_BACKEND`, `QUARK_DATABASE_URL` | The PostgreSQL every instance shares; the Makefile sets both |

A failing test prints the last 40 lines of every instance's log.
