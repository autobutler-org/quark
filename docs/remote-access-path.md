<!-- cspell:words netcheck natpmp upnp tsnetbridge tftpl ODROID -->

# Remote access: direct or relayed? (#3883)

Away from home, image loads were taking 3–4 s even on a fast link. The likely cause is that phone↔Quark
traffic was going through a shared public relay instead of a direct peer-to-peer path. Until now nothing
recorded which path was in use. This page covers what each side now records, how to take the measurements
the issue asks for, and what the code alone already shows.

Everything below is debug tooling. None of it is shown to users, and none of it holds a key, token,
account name, file path, or full IP address (the #3613 redaction rules). A direct path is labeled only
`lan` or `internet`, by whether the address is private.

## What is recorded

### On the Quark

- **Server log.** The remote-access node reads its peers every 15 s and logs a line when a peer first
  carries traffic and again each time it moves between direct and relayed:

  ```text
  [remote] path to iOS peer 1: relay (nyc)
  [remote] path to iOS peer 1 changed: relay (nyc) -> direct (internet)
  ```

  It also logs the network check when the first one lands and whenever it changes:

  ```text
  [remote] network check: udp=true ipv4=true ipv6=false mapping-varies-by-destination=no upnp=no nat-pmp=no pcp=no relay=nyc (18.2 ms)
  ```

  `mapping-varies-by-destination=yes` means a symmetric NAT, which hole punching usually cannot get
  through. `upnp`, `nat-pmp` and `pcp` say whether the router offers port mapping. Peers are named by OS
  and the order they were first seen, never by their key or hostname.
  (`pkg/util/remoteutil/path.go`)

- **Admin endpoint.** `GET /api/v0/settings/remote-access/paths` (admins only) returns the same data
  on demand: `connected`, the last `network` check, and one entry per peer with `path` (`direct`, `relay`,
  `peer-relay`, `idle`), `network`, `relayRegion`, `lastHandshake`, `rxBytes` and `txBytes`. The network
  check refreshes on its own every half minute or so while the node is active. `at` gives its age.

### On the phone

The bridge (`packages/tailnet_flutter/cmd/tsnetbridge/diag.go`) keeps:

- the Quark peer's current path, relay region, last handshake and byte counts;
- the phone's own network check: UDP, whether its NAT maps per destination, router port mapping, and
  its preferred relay's latency;
- the last 32 path changes, each with a timestamp, read every 5 s while the node runs;
- the last 64 requests the local proxy carried, each with its route (only the first segment after
  `/api/v0`, so `files` or `thumbnails`), status, time to response headers, time to the end of the body,
  and size.

`EmbeddedTunnel.peerStatus()` returns all of that. `EmbeddedTunnel.ping(count: n)` pings the Quark `n`
times inside the tunnel, which reports min/avg RTT and whether the answer came direct or via a relay. It
also opens `n` TCP connections to the Quark through the tunnel, the same dial the proxy makes. A **debug
build** logs new path changes and request timings to the `quark.tunnel` log every 30 s
(`TunnelPathLog`). Release builds do not.

## How to measure

For each network in the matrix:

1. Fully close and reopen the app (a cold node, #3882). Open Photos and let the thumbnail grid load.
   Note the time from opening the page to a full grid.
2. Open one full-size image and one large folder listing. In the `quark.tunnel` log, read the
   `request thumbnails …`, `request files …` lines for headers and body times.
3. From DevTools (or a debug hook), run `EmbeddedTunnel.ping(count: 10)` and record `tunnel.path`,
   `tunnel.minMs`/`avgMs` and `tcp.minMs`/`avgMs`.
4. Download a ~10 MB file and read its `bodyMs` and `bytes` from the request log. Throughput is
   bytes ÷ bodyMs.
5. Read `EmbeddedTunnel.peerStatus()['network']` for the phone's NAT. On the Quark, run
   `GET /settings/remote-access/paths` and read the phone's entry and the Quark's network check. A
   phone that stays `relay` after traffic has flowed for a minute could not be reached directly.
6. Wait two minutes with traffic flowing and repeat step 3, to see whether the path upgraded from relay
   to direct.

| Network           | Path (cold → after 2 min) | Tunnel RTT min/avg | TCP RTT | 10 MB time | Grid load | Phone NAT | Quark NAT |
| ----------------- | ------------------------- | ------------------ | ------- | ---------- | --------- | --------- | --------- |
| Home Wi-Fi        |                           |                    |         |            |           |           |           |
| Coffee shop Wi-Fi |                           |                    |         |            |           |           |           |
| LTE/5G            |                           |                    |         |            |           |           |           |
| Phone tethering   |                           |                    |         |            |           |           |           |

For NAT, record whether the mapping varies by destination and which of UPnP, NAT-PMP and PCP answered.

The numbers need someone on each of those networks with a debug build and a Quark on the new code. Record
them in #3883.

## What the code already shows

These do not need measuring. They explain why a relayed path is likely and why it is slow when it happens.

- **The Quark's UDP port is random.** `startLocked` builds the node without a fixed `Port`
  (`pkg/util/remoteutil/helpers.go`), so it cannot be port-forwarded or allow-listed on the home router.
  Unless the router offers UPnP, NAT-PMP or PCP (the network check now says), a phone behind a NAT that
  maps per destination cannot reach it directly.
- **Every new node starts relayed.** Each node starts on its home relay and upgrades to direct only after
  disco pings succeed. The app restarts the phone's node after a background return that fails its health
  check (#3882), so each of those restarts begins cold.
- **The relays are public and shared.** The coordination server publishes the networking library's
  default relay map, and our own relay is off (iac `setup-headscale.bash.tftpl`). UDP 3478 is open on the
  coordination VM, but nothing listens on it.
- **Docker adds a NAT.** The Quark appliance runs the binary as a system service, so this does not apply
  there. A Quark in a container on bridge networking (`docs/container.md`) maps only the HTTP port, which
  puts a second NAT in front of the node's UDP.
- **The Quark-side TLS loopback hop** (`newProxy` with `localTLS`) re-encrypts each request to the Quark
  itself. That costs CPU on the ODROID but adds no network round trip. The request timings above include
  it.

## Recommendation

Pending the matrix above, the code-level findings point to three changes, in this order:

1. **Give the Quark's node a fixed UDP port**, and ask the router to map it with UPnP/NAT-PMP/PCP where
   available. That gives the phone something stable to punch through to, and gives a user who forwards a
   port by hand something to forward (#4273).
2. **Run our own relay near users**: turn on the coordination server's embedded relay and a real STUN
   listener on 3478, or remove the dead 3478 rule if we stay on public relays. That bounds the cost of the
   relayed case (#4274).
3. **Keep the phone's node warm across resume** (#3882), so a return from the background does not throw
   away a direct path.
