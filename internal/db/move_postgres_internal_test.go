package db

import (
	"slices"
	"testing"
	"time"
)

func TestConvertForPostgres(t *testing.T) {
	at := time.Date(2026, 8, 28, 16, 4, 23, 0, time.UTC)
	for _, tc := range []struct {
		name     string
		value    any
		dataType string
		want     any
	}{
		{"nil stays nil", nil, "bigint", nil},
		{"a time", at.In(time.FixedZone("PDT", -7*3600)), "timestamp with time zone", at},
		{"datetime text", "2026-08-28 16:04:23", "timestamp with time zone", at},
		{"RFC 3339 text", "2026-08-28T16:04:23Z", "timestamp with time zone", at},
		{"an integer flag", int64(1), "boolean", true},
		{"a zero flag", int64(0), "boolean", false},
		{"a bool", true, "boolean", true},
		{"an integer", int64(7), "bigint", int64(7)},
		{"an integer in a real", int64(2), "double precision", float64(2)},
		{"text in a blob", "abc", "bytea", []byte("abc")},
		{"a blob in text", []byte("abc"), "text", "abc"},
		{"a number in text", int64(42), "text", "42"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got, err := convertForPostgres(tc.value, tc.dataType)
			if err != nil {
				t.Fatalf("convertForPostgres(%v, %q): %v", tc.value, tc.dataType, err)
			}
			if gotTime, ok := got.(time.Time); ok {
				if !gotTime.Equal(tc.want.(time.Time)) || gotTime.Location() != time.UTC {
					t.Fatalf("convertForPostgres(%v, %q) = %v, want %v in UTC", tc.value, tc.dataType, got, tc.want)
				}
				return
			}
			if gotBytes, ok := got.([]byte); ok {
				if string(gotBytes) != string(tc.want.([]byte)) {
					t.Fatalf("convertForPostgres(%v, %q) = %q, want %q", tc.value, tc.dataType, got, tc.want)
				}
				return
			}
			if got != tc.want {
				t.Fatalf("convertForPostgres(%v, %q) = %#v, want %#v", tc.value, tc.dataType, got, tc.want)
			}
		})
	}

	for _, tc := range []struct {
		value    any
		dataType string
	}{
		{"yesterday", "timestamp with time zone"},
		{"1", "bigint"},
		{1.5, "boolean"},
		{int64(1), "uuid"},
	} {
		if got, err := convertForPostgres(tc.value, tc.dataType); err == nil {
			t.Errorf("convertForPostgres(%#v, %q) = %#v, want an error", tc.value, tc.dataType, got)
		}
	}
}

func TestDependencyOrder(t *testing.T) {
	got, err := dependencyOrder(
		[]string{"sessions", "photo_albums", "users", "group_members", "groups"},
		map[string][]string{
			"sessions":      {"users"},
			"photo_albums":  {"photo_albums", "users"},
			"group_members": {"groups", "users"},
		},
	)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"groups", "users", "group_members", "photo_albums", "sessions"}
	if !slices.Equal(got, want) {
		t.Fatalf("dependencyOrder = %v, want %v", got, want)
	}

	if _, err := dependencyOrder([]string{"a", "b"}, map[string][]string{"a": {"b"}, "b": {"a"}}); err == nil {
		t.Fatal("dependencyOrder accepted a cycle")
	}
}
