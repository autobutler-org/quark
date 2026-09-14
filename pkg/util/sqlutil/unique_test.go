package sqlutil_test

import (
	"database/sql"
	"errors"
	"fmt"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

func TestIsUniqueConstraintErr(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want bool
	}{
		{"nil is not a constraint error", nil, false},
		{"ErrNoRows is not a constraint error", sql.ErrNoRows, false},
		{"unrelated error", errors.New("connection refused"), false},
		{"bare UNIQUE constraint failed", errors.New("UNIQUE constraint failed"), true},
		{"driver-prefixed constraint error",
			errors.New("constraint failed: UNIQUE constraint failed: photo_albums.name"), true},
		{"expression index constraint error",
			errors.New("constraint failed: UNIQUE constraint failed: index 'idx_photo_albums_sibling_name'"), true},
		{"wrapped constraint error",
			fmt.Errorf("ensure album: %w", errors.New("UNIQUE constraint failed: photo_albums.name")), true},
		{"lowercase does not match", errors.New("unique constraint failed"), false},
		{"other constraint kinds do not match",
			errors.New("NOT NULL constraint failed: photo_albums.name"), false},
		{"FOREIGN KEY constraint does not match",
			errors.New("FOREIGN KEY constraint failed"), false},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := sqlutil.IsUniqueConstraintErr(tt.err); got != tt.want {
				t.Errorf("IsUniqueConstraintErr(%v) = %v, want %v", tt.err, got, tt.want)
			}
		})
	}
}
