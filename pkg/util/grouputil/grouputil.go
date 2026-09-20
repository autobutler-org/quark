// Package grouputil manages the groups admins put accounts in (#1910). A group
// can be shared a path like an account can; the built-in everyone group
// includes every active account and can't be changed.
//
// Every group has a folder, groups/<name> on the internal device, which the
// group may write to (#2016). It is made with the group, moves when the group
// is renamed, and stays when the group is deleted, admin-only from then on.
package grouputil

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// The sentinels' text is written for the app to show, so handlers send it out
// unwrapped.
var (
	// ErrGroupNotFound reports a group id that names no group.
	ErrGroupNotFound = errors.New("no group has that id")
	// ErrGroupNameTaken reports a name another group already has, ignoring case.
	ErrGroupNameTaken = errors.New("a group with that name already exists")
	// ErrInvalidGroupName reports a name that is empty, too long, holds a
	// control character or a slash, or is . or .. once trimmed. The name is
	// also the group's folder, so it has to be one path segment.
	ErrInvalidGroupName = errors.New("a group name has 1 to 64 characters, isn't . or .., and has no slashes, line breaks or tabs")
	// ErrGroupFolderTaken reports a rename onto a name whose folder already
	// exists in groups/ and is not the group's own.
	ErrGroupFolderTaken = errors.New("a folder with that name is already in groups; move or rename it first")
	// ErrBuiltinGroup reports a change to the everyone group.
	ErrBuiltinGroup = errors.New("the everyone group always includes every account")
	// ErrNotMember reports removing an account that is not in the group.
	ErrNotMember = errors.New("that account isn't in this group")
)

// Member is an account in a group.
type Member struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

// Group is a group and its members. The everyone group lists no members: it
// includes every active account without a row for each.
type Group struct {
	ID      int64    `json:"id"`
	Name    string   `json:"name"`
	Builtin bool     `json:"builtin"`
	Members []Member `json:"members"`
}

// ListGroupsParams lists every group.
type ListGroupsParams struct {
	Database *db.DatabaseSqlc
}

// ListGroupsResult is every group, everyone first and the rest by name.
type ListGroupsResult struct {
	Groups []Group
}

// ListGroups lists every group with its members.
func ListGroups(ctx context.Context, params ListGroupsParams) (ListGroupsResult, error) {
	rows, err := params.Database.Queries.ListGroups(ctx)
	if err != nil {
		return ListGroupsResult{}, err
	}
	memberships, err := params.Database.Queries.ListGroupMembers(ctx)
	if err != nil {
		return ListGroupsResult{}, err
	}
	members := make(map[int64][]Member, len(rows))
	for _, m := range memberships {
		members[m.GroupID] = append(members[m.GroupID], Member{ID: m.UserID, Username: m.Username})
	}
	groups := make([]Group, 0, len(rows))
	for _, row := range rows {
		group := groupFromRow(row)
		if m := members[row.ID]; m != nil {
			group.Members = m
		}
		groups = append(groups, group)
	}
	return ListGroupsResult{Groups: groups}, nil
}

// CreateGroupParams creates a group.
type CreateGroupParams struct {
	Database *db.DatabaseSqlc
	// FilesDir is the internal device's files directory, where the group's
	// folder is made.
	FilesDir string
	Name     string
}

// CreateGroupResult is the new group, with no members, and its folder.
type CreateGroupResult struct {
	Group Group
	// FolderPath is the group's folder, groups/<name>, relative to FilesDir.
	FolderPath string
}

// CreateGroup creates an empty group, its folder groups/<name>, and the one
// row granting the group write there. The name is trimmed first. An existing
// folder of that name is adopted rather than refused, as a home is.
func CreateGroup(ctx context.Context, params CreateGroupParams) (CreateGroupResult, error) {
	name, err := validateName(params.Name)
	if err != nil {
		return CreateGroupResult{}, err
	}
	if params.FilesDir == "" {
		return CreateGroupResult{}, errors.New("files directory not set")
	}
	var result CreateGroupResult
	madeDir := ""
	err = inTx(ctx, params.Database, func(q *db.Queries) error {
		row, err := q.CreateGroup(ctx, name)
		if sqlutil.IsUniqueConstraintErr(err) {
			return ErrGroupNameTaken
		}
		if err != nil {
			return err
		}
		result.Group = groupFromRow(row)
		madeDir, err = createFolder(ctx, q, params.FilesDir, name, row.ID)
		if err != nil {
			return err
		}
		result.FolderPath = folderRelPath(name)
		return nil
	})
	if err != nil {
		if madeDir != "" {
			// Best-effort, and only a folder this call made; the error that got
			// here is the one worth reporting.
			_ = os.Remove(madeDir)
		}
		return CreateGroupResult{}, err
	}
	return result, nil
}

// RenameGroupParams renames a group.
type RenameGroupParams struct {
	Database *db.DatabaseSqlc
	// Registry, Storage and EventBus move the group's folder the way any
	// other move goes, so its access rows, favorites and album items follow.
	Registry vfs.Registry
	Storage  *storageutil.StorageService
	EventBus *eventbus.Bus
	// FilesDir is the internal device's files directory, where the group's
	// folder is.
	FilesDir string
	GroupID  int64
	Name     string
}

// RenameGroupResult is the renamed group. Members are not loaded.
type RenameGroupResult struct {
	Group Group
	// OldFolderPath and FolderPath are the group's folder before and after,
	// relative to FilesDir. They are equal when only the group row changed.
	OldFolderPath string
	FolderPath    string
}

// RenameGroup renames a group and moves its folder to match. A group can take
// its own name in another case. A folder already at the new name is
// ErrGroupFolderTaken; a missing folder is made at the old name first, so the
// move carries whatever rows still point there.
func RenameGroup(ctx context.Context, params RenameGroupParams) (RenameGroupResult, error) {
	name, err := validateName(params.Name)
	if err != nil {
		return RenameGroupResult{}, err
	}
	if params.FilesDir == "" {
		return RenameGroupResult{}, errors.New("files directory not set")
	}
	queries := params.Database.Queries
	group, err := changeableGroup(ctx, queries, params.GroupID)
	if err != nil {
		return RenameGroupResult{}, err
	}
	row, err := queries.RenameGroup(ctx, db.RenameGroupParams{Name: name, ID: params.GroupID})
	switch {
	case sqlutil.IsUniqueConstraintErr(err):
		return RenameGroupResult{}, ErrGroupNameTaken
	case errors.Is(err, sql.ErrNoRows):
		return RenameGroupResult{}, ErrGroupNotFound
	case err != nil:
		return RenameGroupResult{}, err
	}
	oldRel, newRel := folderRelPath(group.Name), folderRelPath(name)
	result := RenameGroupResult{Group: groupFromRow(row), OldFolderPath: oldRel, FolderPath: newRel}
	if oldRel == newRel {
		return result, nil
	}
	if err := renameFolder(ctx, params, group.Name, name); err != nil {
		// Put the name back so the group and its folder still agree.
		if _, undoErr := queries.RenameGroup(context.WithoutCancel(ctx), db.RenameGroupParams{Name: group.Name, ID: params.GroupID}); undoErr != nil {
			slog.Error("groups: could not undo a rename whose folder did not move", "group", group.Name, "err", undoErr)
		}
		return RenameGroupResult{}, err
	}
	return result, nil
}

// DeleteGroupParams deletes a group.
type DeleteGroupParams struct {
	Database *db.DatabaseSqlc
	GroupID  int64
}

// DeleteGroupResult is empty: a delete either happens or returns an error.
type DeleteGroupResult struct{}

// DeleteGroup deletes a group. Its memberships and the access it was granted
// go with it, so its members lose whatever only the group gave them. Its
// folder and everything in it stay: with the group's row gone the folder is
// admin-only, for an admin to hand to someone else or remove.
func DeleteGroup(ctx context.Context, params DeleteGroupParams) (DeleteGroupResult, error) {
	if _, err := changeableGroup(ctx, params.Database.Queries, params.GroupID); err != nil {
		return DeleteGroupResult{}, err
	}
	n, err := params.Database.Queries.DeleteGroup(ctx, params.GroupID)
	if err != nil {
		return DeleteGroupResult{}, err
	}
	if n == 0 {
		return DeleteGroupResult{}, ErrGroupNotFound
	}
	return DeleteGroupResult{}, nil
}

// AddMemberParams puts an account in a group.
type AddMemberParams struct {
	Database *db.DatabaseSqlc
	GroupID  int64
	UserID   int64
}

// AddMemberResult reports whether the account was not already a member.
type AddMemberResult struct {
	Added bool
}

// AddMember puts an active account in a group. Only an active account can
// join; a disabled one keeps the memberships it already has. Adding a member
// again is not an error. For an account that is missing, pending or disabled
// it returns authutil.ErrUserNotFound.
func AddMember(ctx context.Context, params AddMemberParams) (AddMemberResult, error) {
	queries := params.Database.Queries
	if _, err := changeableGroup(ctx, queries, params.GroupID); err != nil {
		return AddMemberResult{}, err
	}
	user, err := queries.GetUserByID(ctx, params.UserID)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && user.Status != authutil.StatusActive) {
		return AddMemberResult{}, authutil.ErrUserNotFound
	}
	if err != nil {
		return AddMemberResult{}, err
	}
	n, err := queries.AddGroupMember(ctx, db.AddGroupMemberParams{GroupID: params.GroupID, UserID: params.UserID})
	if err != nil {
		return AddMemberResult{}, err
	}
	return AddMemberResult{Added: n > 0}, nil
}

// RemoveMemberParams takes an account out of a group.
type RemoveMemberParams struct {
	Database *db.DatabaseSqlc
	GroupID  int64
	UserID   int64
}

// RemoveMemberResult is empty: a removal either happens or returns an error.
type RemoveMemberResult struct{}

// RemoveMember takes an account out of a group, whatever its status.
func RemoveMember(ctx context.Context, params RemoveMemberParams) (RemoveMemberResult, error) {
	queries := params.Database.Queries
	if _, err := changeableGroup(ctx, queries, params.GroupID); err != nil {
		return RemoveMemberResult{}, err
	}
	n, err := queries.RemoveGroupMember(ctx, db.RemoveGroupMemberParams{GroupID: params.GroupID, UserID: params.UserID})
	if err != nil {
		return RemoveMemberResult{}, err
	}
	if n == 0 {
		return RemoveMemberResult{}, ErrNotMember
	}
	return RemoveMemberResult{}, nil
}

// RepairGroupFoldersParams is the Quark whose group folders are repaired.
type RepairGroupFoldersParams struct {
	Database *db.DatabaseSqlc
	// FilesDir is the internal device's files directory, where group folders
	// live.
	FilesDir string
}

// RepairGroupFoldersResult names the groups that were given their folder.
type RepairGroupFoldersResult struct {
	Repaired []string
}

// RepairGroupFolders gives every group with no row of its own on
// groups/<name> write there, making the directory when it is missing (#2016).
// That covers the everyone group, whose folder nobody creates by hand, and
// every group made before groups had folders.
//
// Like authutil.RepairHomes it runs at startup and keys on the missing row,
// never the missing directory, so an existing folder is adopted and a second
// run does nothing. It also means a group's own row on its folder, removed by
// hand, comes back at the next restart; a lower level set there stays.
func RepairGroupFolders(ctx context.Context, params RepairGroupFoldersParams) (RepairGroupFoldersResult, error) {
	var result RepairGroupFoldersResult
	if params.Database == nil {
		return result, errors.New("database not initialized")
	}
	if params.FilesDir == "" {
		return result, errors.New("files directory not set")
	}
	groups, err := params.Database.Queries.ListGroupsMissingFolder(ctx)
	if err != nil {
		return result, fmt.Errorf("list the groups with no folder: %w", err)
	}
	for _, group := range groups {
		// A group named before names had to be one path segment keeps no
		// folder rather than being given one somewhere else in the tree.
		if validateFolderName(group.Name) != nil {
			slog.Warn("no group folder repaired: the name is not a folder name", "group", group.Name)
			continue
		}
		if err := os.MkdirAll(filepath.Join(params.FilesDir, authutil.GroupsDirName, group.Name), 0o755); err != nil {
			return result, fmt.Errorf("create the folder of %q: %w", group.Name, err)
		}
		if err := grantFolder(ctx, params.Database.Queries, group.Name, group.ID); err != nil {
			return result, err
		}
		result.Repaired = append(result.Repaired, group.Name)
	}
	return result, nil
}
