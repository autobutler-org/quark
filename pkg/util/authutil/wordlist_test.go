package authutil_test

import (
	"regexp"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/authutil"
)

// TestWordlist pins what the recovery phrase's strength rests on: 256
// distinct words, 8 bits each. The list held 232 while its comments claimed
// 256, overstating a 6-word phrase by about a bit (#2153), and a duplicate
// would quietly cost more.
func TestWordlist(t *testing.T) {
	if got := len(authutil.Wordlist); got != 256 {
		t.Fatalf("wordlist has %d words, want 256", got)
	}
	word := regexp.MustCompile(`^[a-z]+$`)
	seen := make(map[string]bool, len(authutil.Wordlist))
	for _, w := range authutil.Wordlist {
		if seen[w] {
			t.Errorf("%q appears twice", w)
		}
		seen[w] = true
		// Phrases are joined with "-" and normalized to lower case, so a word
		// has to survive both unchanged.
		if !word.MatchString(w) {
			t.Errorf("%q is not a lowercase word", w)
		}
	}
}
