package grouputil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"path"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// maxNameRunes is the longest a group name may be, in characters.
const maxNameRunes = 64

// validateName trims a group name and returns ErrInvalidGroupName when what is
// left is empty, longer than maxNameRunes, not UTF-8, holds a control
// character, or is not one path segment.
func validateName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" || !utf8.ValidString(name) || utf8.RuneCountInString(name) > maxNameRunes ||
		strings.ContainsFunc(name, unicode.IsControl) {
		return "", ErrInvalidGroupName
	}
	if err := validateFolderName(name); err != nil {
		return "", err
	}
	return name, nil
}

// validateFolderName returns ErrInvalidGroupName for a name that is not one
// path segment, so groups/<name> cannot climb out of groups/ or reach inside
// another folder. Names from before this rule may still be stored.
func validateFolderName(name string) error {
	if name == "" || name == "." || name == ".." || strings.ContainsAny(name, `/\`) {
		return ErrInvalidGroupName
	}
	return nil
}

// folderRelPath is a group's folder, groups/<name>, relative to the files
// directory. ListGroupsMissingFolder spells the same path in SQL.
func folderRelPath(name string) string {
	return path.Join(authutil.GroupsDirName, name)
}

// inTx runs fn in one transaction, rolling back when it returns an error.
func inTx(ctx context.Context, database *db.DatabaseSqlc, fn func(*db.Queries) error) error {
	tx, err := database.Db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(database.Queries.WithTx(tx)); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

// grantFolder gives a group write on its folder: one row, so membership alone
// decides who reaches it. Written straight to the table for the reason
// authutil.grantHome gives.
func grantFolder(ctx context.Context, queries *db.Queries, name string, groupID int64) error {
	if err := queries.SetGroupPathAccess(ctx, db.SetGroupPathAccessParams{
		RelPath: folderRelPath(name),
		GroupID: sql.NullInt64{Int64: groupID, Valid: true},
		Level:   "write",
	}); err != nil {
		return fmt.Errorf("grant the folder of %q: %w", name, err)
	}
	return nil
}

// createFolder makes a group's folder in files and grants it. An existing
// folder is adopted; madeDir is the directory this call made, empty for an
// adopted one, so a caller whose transaction fails removes only that.
func createFolder(ctx context.Context, queries *db.Queries, files vfs.VFS, name string, groupID int64) (madeDir string, err error) {
	// The name is validated, so it is one path segment.
	rel := folderRelPath(name)
	made, err := authutil.MakeFolder(ctx, files, rel)
	if err != nil {
		return "", fmt.Errorf("create the folder of %q: %w", name, err)
	}
	if made {
		madeDir = rel
	}
	if err := grantFolder(ctx, queries, name, groupID); err != nil {
		return madeDir, err
	}
	return madeDir, nil
}

// ensureFolderFree returns ErrGroupFolderTaken when something other than the
// group's own folder is already at newRel. On a case-insensitive disk a
// rename that only changes case finds its own folder there, which is fine:
// the parent then lists only the old spelling, where a case-sensitive disk
// holding both lists each.
func ensureFolderFree(ctx context.Context, files vfs.VFS, oldRel, newRel string) error {
	_, err := files.Stat(ctx, newRel)
	if errors.Is(err, vfs.ErrNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	if !strings.EqualFold(oldRel, newRel) {
		return ErrGroupFolderTaken
	}
	siblings, err := files.List(ctx, path.Dir(newRel), nil)
	if err != nil {
		return err
	}
	newName := path.Base(newRel)
	for _, sibling := range siblings {
		if sibling.Name == newName {
			return ErrGroupFolderTaken
		}
	}
	return nil
}

// renameFolder moves a group's folder from groups/<oldName> to
// groups/<newName> through the ordinary move, which carries the access rows,
// favorites and album items on it and publishes the move. A missing folder is
// made first, so rows still pointing at it move too. A name from before names
// had to be one path segment has no folder to move, so the group gets a new
// one instead.
func renameFolder(ctx context.Context, params RenameGroupParams, files vfs.VFS, oldName, newName string) error {
	if validateFolderName(oldName) != nil {
		_, err := createFolder(ctx, params.Database.Queries, files, newName, params.GroupID)
		return err
	}
	oldRel, newRel := folderRelPath(oldName), folderRelPath(newName)
	if err := ensureFolderFree(ctx, files, oldRel, newRel); err != nil {
		return err
	}
	if err := files.MkdirAll(ctx, oldRel); err != nil {
		return fmt.Errorf("create the folder of %q: %w", oldName, err)
	}
	if _, err := fileutil.MoveFile(fileutil.MoveFileParams{
		Ctx:         ctx,
		Registry:    params.Registry,
		EventBus:    params.EventBus,
		Database:    params.Database,
		OldFilePath: oldRel,
		NewFilePath: newRel,
	}); err != nil {
		return fmt.Errorf("move the folder of %q: %w", oldName, err)
	}
	return nil
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
