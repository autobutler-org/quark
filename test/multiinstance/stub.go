// Package multiinstance runs several Quark instances against one PostgreSQL and
// one shared files directory, behind a load balancer with no affinity, and
// checks the cases epic #2964 names: sessions, shared file writes, job
// ownership, cross-instance events, split uploads and downloads, login lockout
// and a rolling upgrade (#2971).
//
// Test sources use //go:build multiinstance so ordinary unit tests skip them.
// Run: make test/multiinstance (needs make serve/postgres). See README.md.
package multiinstance
