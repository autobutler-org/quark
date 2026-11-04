//go:build !race

package indexutil

// equivSeeds is how many randomized event sequences
// TestFileIndexMatchesReference runs.
func equivSeeds() int { return 12 }
