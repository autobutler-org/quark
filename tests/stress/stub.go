// Package stress holds defensive API stress/chaos checks for Quark.
//
// Test sources use //go:build stress so ordinary unit CI stays green.
// Run: make test/stress   or   go test -tags stress ./tests/stress/
package stress
