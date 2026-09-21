// Package chaos holds defensive API stress/chaos checks for Quark.
//
// Test sources use //go:build chaos so ordinary unit tests skip them.
// Run: make test/chaos   or   go test -tags chaos ./test/chaos/
package chaos
