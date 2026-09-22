# Where Quark's Logs Go

Quark writes to stdout and stderr and lets the platform own the rest. Where they land depends on how
it was installed.

## Linux (systemd)

`quark install` writes a unit that sets no output redirection, so journald takes both streams:

```bash
journalctl -u quark           # everything
journalctl -u quark -f        # follow
journalctl -u quark -p err    # errors only
journalctl -u quark --since "1 hour ago"
```

journald applies its own size limits and rotation, so nothing here can fill the disk on its own. If
`journalctl -u quark` prints nothing on a machine installed before this changed, re-run
`quark install` — the old unit appended to a file instead.

## macOS (launchd)

There is no journald, so the daemon writes files:

```text
/var/log/quark.log       # stdout
/var/log/quark.err.log   # stderr
```

`quark install` also writes `/etc/newsyslog.d/quark.conf`, which rotates each one at 10 MB and keeps
five compressed generations. Without it a crash loop fills the disk: a failed start prints the whole
usage text, and `KeepAlive` retries forever.

launchd holds the file open, so a rotation while the daemon is running leaves it appending to the
rotated file until it next restarts. Restart it to get back onto the live path:

```bash
sudo launchctl kickstart -k system/org.autobutler.quark
```

## Docker

The entrypoint runs in the foreground, so the container runtime collects both streams:

```bash
docker logs -f quark
kubectl logs -f deployment/quark
```

See [Container Image](./container.md) for the rest of the deployment notes.

## Older installs

Installs made before this wrote to `/var/log/quark.app` and `/var/log/quark.err`. Neither rotated,
and nothing read them. `quark install` deletes both, so re-running it is how an existing machine
reclaims that space — check their size first if you want to keep what is in them.
