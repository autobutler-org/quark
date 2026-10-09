package indexutil

import (
	"strings"
	"unicode/utf8"
)

func newNameMatcher(query string) nameMatcher {
	lower := strings.ToLower(query)
	return nameMatcher{lower: lower, all: query == "", ascii: isASCII(lower)}
}

// matches reports whether name holds the query. strings.ToLower changes only
// A-Z in an ASCII name, so the query's lowercase form can be found in one by
// folding those bytes, and only when it is ASCII itself.
func (m nameMatcher) matches(name string) bool {
	switch {
	case m.all:
		return true
	case !isASCII(name):
		return strings.Contains(strings.ToLower(name), m.lower)
	case !m.ascii:
		return false
	}
	for i := 0; i+len(m.lower) <= len(name); i++ {
		j := 0
		for j < len(m.lower) && lowerASCII(name[i+j]) == m.lower[j] {
			j++
		}
		if j == len(m.lower) {
			return true
		}
	}
	return false
}

// isASCII reports whether s is all ASCII.
func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= utf8.RuneSelf {
			return false
		}
	}
	return true
}

// lowerASCII lowercases an ASCII letter and leaves any other byte alone.
func lowerASCII(b byte) byte {
	if 'A' <= b && b <= 'Z' {
		return b + 'a' - 'A'
	}
	return b
}
