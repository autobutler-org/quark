# Power-cut suite

Cuts the power under Quark's upload and vault write paths and checks that nothing is corrupted (#2517). What
the guarantees are and why they hold is in [`docs/architecture/durability.md`](../../../docs/architecture/durability.md);
this directory is how they are tested.

```bash
make test/chaos/powercut
```

It needs Docker and nothing else. CI runs it as the `power-cut` job in `.github/workflows/test.yml`.

## Why a file system, not `kill -9`

Killing the process is not a power cut. The kernel still holds everything the process wrote, and writes it out
afterwards, so a `kill -9` never shows a file whose name reached the disk before its bytes did — the defect #2517
found. [LazyFS](https://github.com/dsrhaslab/lazyfs) is a FUSE file system that keeps data not yet flushed in its own
memory and writes it to the directory underneath only on `fsync`. Killing LazyFS therefore loses exactly what a
power cut loses, and the directory underneath is exactly what reached the disk.

## What a run does

For every case, `run.bash`:

1. mounts a fresh LazyFS;
2. starts `powercut write <scenario>` on the mount, which performs a stream of operations through Quark's own
   code and appends each to a ledger outside the mount once Quark reports it done — what a client was told
   succeeded;
3. after a delay, arms a crash fault: at the next file-system call matching it, LazyFS kills itself;
4. runs `powercut check <scenario>` against the directory LazyFS was backed by.

The check fails on any acknowledged operation that did not survive, and on anything half-written sitting where
a user would see it. Each case runs `POWERCUT_ROUNDS` times (default 3), armed at a different moment each round.

| Scenario | Write path under test                                                                     | The check                                                                                          |
| -------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `upload` | `LocalVFS.Write`, `LocalVFS.MoveFileIn`, `storageutil.UploadFilesStreamedImpl` in turn     | every acknowledged file holds its full content; every file a listing shows does too                |
| `vault`  | `vaultutil.Setup`, `CreateEntry`, and a `ChangePassword` every ten entries                 | `integrity_check` passes; it unlocks with the last acknowledged password (or the one being set); every acknowledged entry is there and decrypts |

The cut points are listed in `CASES` in `run.bash`: mid-stream into an upload's temp, the instant an upload is
renamed or linked into place, any flush, a vault transaction with its journal on disk but not its database, a
half-written database page, and the commit point.

## Files

| File            | What it is                                                                                      |
| --------------- | ----------------------------------------------------------------------------------------------- |
| `run.bash`      | the orchestrator; `run.bash --help` for running it outside Docker                               |
| `*.go`          | the `powercut` writer and checker, built by the Makefile target                                 |
| `Dockerfile`    | LazyFS, pinned to a commit, built on Ubuntu                                                      |
| `lazyfs.patch`  | builds LazyFS against the distribution's spdlog instead of downloading one at configure time    |

Results, one directory per case with the LazyFS log, writer log, ledger and check output, land in
`test-results/powercut/`. A failed case also keeps `root/`, the disk as the power cut left it.

## Adding a case

A new cut point is one line in `CASES`: a scenario and a LazyFS crash fault
(`timing=before|after::op=<call>::from_rgx=<path>`, plus `to_rgx` for `rename` and `link`). A new write path
gets a scenario: a `write` that acknowledges only what Quark reported done, and a `check` that holds the disk to
the bar. Confirm the case fails against the code it guards before trusting it to pass.
