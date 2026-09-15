package grouputil

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/autobutler-org/quark/internal/db"
)

// maxNameRunes is the longest a group name may be, in characters.
const maxNameRunes = 64

// validateName trims a group name and returns ErrInvalidGroupName when what is
// left is empty, longer than maxNameRunes, not UTF-8, or holds a control
// character.
func validateName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" || !utf8.ValidString(name) || utf8.RuneCountInString(name) > maxNameRunes ||
		strings.ContainsFunc(name, unicode.IsControl) {
		return "", ErrInvalidGroupName
	}
	return name, nil
}

// changeableGroup loads a group an admin may change: ErrGroupNotFound when
// there is none, ErrBuiltinGroup when it is everyone.
func changeableGroup(ctx context.Context, queries *db.Queries, groupID int64) (db.Group, error) {
	group, err := queries.GetGroup(ctx, groupID)
	if errors.Is(err, sql.ErrNoRows) {
		return db.Group{}, ErrGroupNotFound
	}
	if err != nil {
		return db.Group{}, err
	}
	if group.Builtin != 0 {
		return db.Group{}, ErrBuiltinGroup
	}
	return group, nil
}

// groupFromRow is a group with no members yet. Members is never nil, so it
// serializes as [].
func groupFromRow(row db.Group) Group {
	return Group{ID: row.ID, Name: row.Name, Builtin: row.Builtin != 0, Members: []Member{}}
}
