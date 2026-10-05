package iosemutil

import "testing"

// The sizes follow the core count: CPU-bound classes scale with it and never
// drop to zero, and disk copies stay fixed because one disk does not get
// faster with more cores.
func TestClassSlots_FollowCPUs(t *testing.T) {
	cases := []struct {
		cores                   int
		decode, video, raw, cpy int
	}{
		{cores: 1, decode: 2, video: 1, raw: 1, cpy: 2},
		{cores: 4, decode: 2, video: 2, raw: 1, cpy: 2},
		{cores: 8, decode: 4, video: 4, raw: 2, cpy: 2},
		{cores: 16, decode: 8, video: 8, raw: 4, cpy: 2},
	}
	for _, tc := range cases {
		got := [classCount]int{}
		for _, c := range Classes() {
			got[c] = classSlots(c, tc.cores)
		}
		want := [classCount]int{Decode: tc.decode, Video: tc.video, Raw: tc.raw, Copy: tc.cpy}
		if got != want {
			t.Errorf("cores=%d: slots %v, want %v", tc.cores, got, want)
		}
	}
}
