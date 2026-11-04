//go:build race

package indexutil

// equivSeeds is how many randomized event sequences
// TestFileIndexMatchesReference runs.
//
// The race detector makes each SQLite filename search about twenty times
// slower, and the sequences run side by side. Twelve of them outlast the ten
// minutes go test allows a package: on a busy runner the package is still
// inside Search when the alarm fires. Four still draw every event kind. The
// full sample runs without -race.
func equivSeeds() int { return 4 }
