// Package grouputil manages the groups admins put accounts in (#1910). A group
// can be shared a path like an account can; the built-in everyone group
// includes every active account and can't be changed.
package grouputil

import (
	"context"
	"database/sql"
	"errors"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

// The sentinels' text is written for the app to show, so handlers send it out
// unwrapped.
var (
	// ErrGroupNotFound reports a group id that names no group.
	ErrGroupNotFound = errors.New("no group has that id")
	// ErrGroupNameTaken reports a name another group already has, ignoring case.
	ErrGroupNameTaken = errors.New("a group with that name already exists")
	// ErrInvalidGroupName reports a name that is empty, too long, or holds a
	// control character once trimmed.
	ErrInvalidGroupName = errors.New("a group name has 1 to 64 characters and no line breaks or tabs")
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
	Name     string
}

// CreateGroupResult is the new group, with no members.
type CreateGroupResult struct {
	Group Group
}

// CreateGroup creates an empty group. The name is trimmed first.
func CreateGroup(ctx context.Context, params CreateGroupParams) (CreateGroupResult, error) {
	name, err := validateName(params.Name)
	if err != nil {
		return CreateGroupResult{}, err
	}
	row, err := params.Database.Queries.CreateGroup(ctx, name)
	if sqlutil.IsUniqueConstraintErr(err) {
		return CreateGroupResult{}, ErrGroupNameTaken
	}
	if err != nil {
		return CreateGroupResult{}, err
	}
	return CreateGroupResult{Group: groupFromRow(row)}, nil
}

// RenameGroupParams renames a group.
type RenameGroupParams struct {
	Database *db.DatabaseSqlc
	GroupID  int64
	Name     string
}

// RenameGroupResult is the renamed group. Members are not loaded.
type RenameGroupResult struct {
	Group Group
}

// RenameGroup renames a group. A group can take its own name in another case.
func RenameGroup(ctx context.Context, params RenameGroupParams) (RenameGroupResult, error) {
	name, err := validateName(params.Name)
	if err != nil {
		return RenameGroupResult{}, err
	}
	if _, err := changeableGroup(ctx, params.Database.Queries, params.GroupID); err != nil {
		return RenameGroupResult{}, err
	}
	row, err := params.Database.Queries.RenameGroup(ctx, db.RenameGroupParams{Name: name, ID: params.GroupID})
	switch {
	case sqlutil.IsUniqueConstraintErr(err):
		return RenameGroupResult{}, ErrGroupNameTaken
	case errors.Is(err, sql.ErrNoRows):
		return RenameGroupResult{}, ErrGroupNotFound
	case err != nil:
		return RenameGroupResult{}, err
	}
	return RenameGroupResult{Group: groupFromRow(row)}, nil
}

// DeleteGroupParams deletes a group.
type DeleteGroupParams struct {
	Database *db.DatabaseSqlc
	GroupID  int64
}

// DeleteGroupResult is empty: a delete either happens or returns an error.
type DeleteGroupResult struct{}

// DeleteGroup deletes a group. Its memberships and the access it was granted
// go with it, so its members lose whatever only the group gave them.
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
