// Package stress is the capacity harness for a running Quark (#2507). It
// simulates N signed-in clients the way the Flutter app behaves on the Files
// page: one events WebSocket each, the page's refresh every poll interval and
// on every listing event the socket delivers, and a few of them uploading into
// a folder everyone can read, which is what fans one change out to every
// client. It reports throughput, latency per route, errors, event delivery and
// the server's memory for each N.
//
// The sources carry //go:build stress so ordinary unit tests skip them. Run
// make test/stress/capacity, which starts a throwaway backend, or point it at
// one already running with QUARK_BASE_URL, QUARK_USER and QUARK_PASSWORD.
// docs/architecture/capacity.md records what it measured.
package stress
