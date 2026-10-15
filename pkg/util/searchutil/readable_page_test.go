package searchutil_test

import (
	"errors"
	"slices"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/searchutil"
)

// fetchFrom serves ranked pages out of all and records each offset asked for.
func fetchFrom(all []int, offsets *[]int) func(limit, offset int) ([]int, error) {
	return func(limit, offset int) ([]int, error) {
		*offsets = append(*offsets, offset)
		if offset >= len(all) {
			return nil, nil
		}
		return all[offset:min(offset+limit, len(all))], nil
	}
}

// TestReadablePage_FillsThePageAcrossBatches keeps fetching past batches the
// caller can read little of, so the page still comes back full and in rank
// order.
func TestReadablePage_FillsThePageAcrossBatches(t *testing.T) {
	all := make([]int, 40)
	for i := range all {
		all[i] = i
	}
	var offsets []int
	got, err := searchutil.ReadablePage(searchutil.ReadablePageParams[int]{
		Limit:    3,
		Fetch:    fetchFrom(all, &offsets),
		Readable: func(n int) bool { return n%10 == 9 },
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := []int{9, 19, 29}; !slices.Equal(got.Results, want) {
		t.Errorf("Results = %v, want %v", got.Results, want)
	}
	if want := []int{0, 6, 12, 18, 24}; !slices.Equal(offsets, want) {
		t.Errorf("offsets = %v, want batches of twice the limit %v", offsets, want)
	}
}

// TestReadablePage_StopsOnAShortPage returns what it has once a batch comes
// back short, rather than asking again for a page past the end.
func TestReadablePage_StopsOnAShortPage(t *testing.T) {
	var offsets []int
	got, err := searchutil.ReadablePage(searchutil.ReadablePageParams[int]{
		Limit:    5,
		Fetch:    fetchFrom([]int{1, 2, 3, 4}, &offsets),
		Readable: func(n int) bool { return n != 2 },
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := []int{1, 3, 4}; !slices.Equal(got.Results, want) {
		t.Errorf("Results = %v, want %v", got.Results, want)
	}
	if len(offsets) != 1 {
		t.Errorf("fetched %d pages, want 1", len(offsets))
	}
}

// TestReadablePage_ReturnsTheFetchError passes a failed fetch back.
func TestReadablePage_ReturnsTheFetchError(t *testing.T) {
	boom := errors.New("boom")
	_, err := searchutil.ReadablePage(searchutil.ReadablePageParams[int]{
		Limit:    1,
		Fetch:    func(int, int) ([]int, error) { return nil, boom },
		Readable: func(int) bool { return true },
	})
	if !errors.Is(err, boom) {
		t.Errorf("err = %v, want %v", err, boom)
	}
}

// TestSanitizeQuery quotes plain text and passes FTS5 syntax through, but
// quotes text whose quotes or parentheses do not pair up, which FTS5 would
// reject as a syntax error.
func TestSanitizeQuery(t *testing.T) {
	cases := map[string]string{
		"nina simone":  `"nina simone"`,
		"artist:nina":  "artist:nina",
		`say "hi`:      `"say ""hi"`,
		`"say hi"`:     `"say hi"`,
		"(rock OR pop": `"(rock OR pop"`,
		"  ":           `""`,
		"rock AND pop": "rock AND pop",
	}
	for in, want := range cases {
		if got := searchutil.SanitizeQuery(in); got != want {
			t.Errorf("SanitizeQuery(%q) = %q, want %q", in, got, want)
		}
	}
}
