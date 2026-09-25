package chatutil

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/avatarutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// resolvePerms is ResolvePerms on a Queries, which may be a transaction's.
// SQLite has no bitwise-OR aggregate, so the rows come back one by one and
// are joined here.
func resolvePerms(ctx context.Context, queries *db.Queries, channelID, userID int64) (Perms, error) {
	if userID == 0 {
		return 0, nil
	}
	rows, err := queries.ListChatChannelPermsForUser(ctx, db.ListChatChannelPermsForUserParams{
		ChannelID: channelID,
		UserID:    sql.NullInt64{Int64: userID, Valid: true},
	})
	var perms Perms
	for _, row := range rows {
		perms |= Perms(row)
	}
	return perms, err
}

// authorize loads a channel and the caller's effective set on it, and checks
// the caller holds required. An empty set gets ErrChannelNotFound, so the
// caller can't tell the channel exists; a set without required gets
// ErrForbidden. An admin may manage any channel, never read what is in it,
// which this function never guards; their set is whatever their rows give.
func authorize(ctx context.Context, queries *db.Queries, principal accessutil.Principal, channelID int64, required Perms) (db.ChatChannel, Perms, error) {
	channel, err := queries.GetChatChannel(ctx, channelID)
	if errors.Is(err, sql.ErrNoRows) {
		return db.ChatChannel{}, 0, ErrChannelNotFound
	}
	if err != nil {
		return db.ChatChannel{}, 0, err
	}
	perms, err := resolvePerms(ctx, queries, channelID, principal.UserID)
	switch {
	case err != nil:
		return db.ChatChannel{}, 0, err
	case principal.IsAdmin || (perms != 0 && perms.Has(required)):
		return channel, perms, nil
	case perms == 0:
		return db.ChatChannel{}, 0, ErrChannelNotFound
	default:
		return db.ChatChannel{}, 0, ErrForbidden
	}
}

// memberRow is the set on the row for an account or a group, 0 when it has
// none.
func memberRow(ctx context.Context, queries *db.Queries, channelID, userID, groupID int64) (Perms, error) {
	rows, err := queries.ListChatChannelMembers(ctx, channelID)
	if err != nil {
		return 0, err
	}
	for _, row := range rows {
		if (userID != 0 && row.UserID.Int64 == userID) || (groupID != 0 && row.GroupID.Int64 == groupID) {
			return Perms(row.Permissions), nil
		}
	}
	return 0, nil
}

// mayDemote applies the escalation bound to removing or downgrading a row
// (#2415). The target's set is the account's effective one, or the group's
// row: the row is what is being edited. It must be a strict subset of the
// caller's, unless the caller holds manage_channel; the creator's row is
// left to admins, whom the caller has already let through, and to the
// creator themselves.
func mayDemote(ctx context.Context, queries *db.Queries, principal accessutil.Principal, channel db.ChatChannel, callerPerms Perms, userID int64, row Perms) error {
	if userID != 0 && channel.CreatedBy.Valid && channel.CreatedBy.Int64 == userID && userID != principal.UserID {
		return ErrCreatorRow
	}
	if callerPerms.Has(PermManageChannel) {
		return nil
	}
	target := row
	if userID != 0 {
		var err error
		if target, err = resolvePerms(ctx, queries, channel.ID, userID); err != nil {
			return err
		}
	}
	if target&^callerPerms != 0 || target == callerPerms {
		return ErrNotSubset
	}
	return nil
}

// validate trims a name and topic and checks them.
func validate(name, topic string) (string, string, error) {
	name, topic = strings.TrimSpace(name), strings.TrimSpace(topic)
	if name == "" || utf8.RuneCountInString(name) > MaxNameLength || strings.ContainsFunc(name, unicode.IsControl) {
		return "", "", ErrInvalidName
	}
	if utf8.RuneCountInString(topic) > MaxTopicLength {
		return "", "", ErrInvalidTopic
	}
	return name, topic, nil
}

// ensurePrincipal checks that an account is active or that a group exists.
func ensurePrincipal(ctx context.Context, queries *db.Queries, userID, groupID int64) error {
	if userID != 0 {
		user, err := queries.GetUserByID(ctx, userID)
		if errors.Is(err, sql.ErrNoRows) || (err == nil && user.Status != authutil.StatusActive) {
			return accessutil.ErrPrincipalNotFound
		}
		return err
	}
	_, err := queries.GetGroup(ctx, groupID)
	if errors.Is(err, sql.ErrNoRows) {
		return accessutil.ErrPrincipalNotFound
	}
	return err
}

// isEveryone reports whether a group is the built-in everyone group.
func isEveryone(ctx context.Context, queries *db.Queries, groupID int64) (bool, error) {
	group, err := queries.GetGroup(ctx, groupID)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil && group.Builtin != 0 && group.Name == "everyone", err
}

// isPrivate reports whether everyone has no row on a channel.
func isPrivate(ctx context.Context, queries *db.Queries, channelID int64) (bool, error) {
	rows, err := queries.ListChatChannelMembers(ctx, channelID)
	if err != nil {
		return false, err
	}
	for _, row := range rows {
		if row.Builtin != 0 {
			return false, nil
		}
	}
	return true, nil
}

// channelFromRow is a channel as a caller with perms sees it.
func channelFromRow(row db.ChatChannel, perms Perms, private bool) Channel {
	return Channel{
		ID:          row.ID,
		ServerID:    row.ServerID,
		Kind:        row.Kind,
		Name:        row.Name,
		Topic:       row.Topic,
		IsDefault:   row.IsDefault != 0,
		IsPrivate:   private,
		Permissions: perms,
		CreatedBy:   row.CreatedBy.Int64,
		CreatedAt:   row.CreatedAt,
	}
}

// memberUsers is every active account a channel's rows reach, with its
// effective set, by username. The query returns one row per account and
// membership row; this unions them.
func memberUsers(ctx context.Context, queries *db.Queries, channelID int64) ([]ResolvedUser, error) {
	rows, err := queries.ListChatChannelMemberUsers(ctx, channelID)
	if err != nil {
		return nil, err
	}
	users := []ResolvedUser{}
	for _, row := range rows {
		if n := len(users); n > 0 && users[n-1].UserID == row.ID {
			users[n-1].Perms |= Perms(row.Permissions)
			continue
		}
		users = append(users, ResolvedUser{UserID: row.ID, Username: row.Username, Perms: Perms(row.Permissions)})
	}
	return users, nil
}

// memberIDs lists the active accounts a channel's rows reach: everyone who
// sees it.
func memberIDs(ctx context.Context, queries *db.Queries, channelID int64) ([]int64, error) {
	users, err := memberUsers(ctx, queries, channelID)
	ids := make([]int64, 0, len(users))
	for _, user := range users {
		ids = append(ids, user.UserID)
	}
	return ids, err
}

// afterMembershipChange tells everyone who was or now is a member, and returns
// the members as they now stand.
func afterMembershipChange(ctx context.Context, queries *db.Queries, bus *eventbus.Bus, channelID int64, before []int64, dataDir string) (ListMembersResult, error) {
	after, err := memberIDs(ctx, queries, channelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	publish(bus, channelID, append(before, after...))
	return listMembers(ctx, queries, channelID, dataDir)
}

// publish sends chat_channel_changed to an audience. Duplicates are harmless.
func publish(bus *eventbus.Bus, channelID int64, audience []int64) {
	if bus == nil {
		return
	}
	bus.Publish(eventbus.Event{
		Kind: eventbus.EventChatChannelChanged,
		Data: eventbus.ChatChannelChanged{ChannelID: channelID, Audience: audience},
	})
}

// listMembers reads a channel's rows and folds each group's accounts into it.
func listMembers(ctx context.Context, queries *db.Queries, channelID int64, dataDir string) (ListMembersResult, error) {
	rows, err := queries.ListChatChannelMembers(ctx, channelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	groupUsers, err := queries.ListChatChannelGroupUsers(ctx, channelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	// ponytail: one stat per account shown, everyone listing every account.
	// Cache versions in memory if a household grows enough for it to show.
	users := map[int64][]MemberUser{}
	for _, row := range groupUsers {
		users[row.GroupID.Int64] = append(users[row.GroupID.Int64], MemberUser{
			ID:              row.UserID,
			Username:        row.Username,
			AvatarUpdatedAt: avatarVersion(dataDir, row.UserID),
		})
	}
	members := make([]Member, 0, len(rows))
	for _, row := range rows {
		member := Member{
			UserID:      row.UserID.Int64,
			GroupID:     row.GroupID.Int64,
			Name:        row.Name,
			Builtin:     row.Builtin != 0,
			Permissions: Perms(row.Permissions),
		}
		if row.UserID.Valid {
			member.AvatarUpdatedAt = avatarVersion(dataDir, row.UserID.Int64)
		} else {
			member.Users = users[row.GroupID.Int64]
		}
		members = append(members, member)
	}
	return ListMembersResult{Members: members}, nil
}

// avatarVersion is a user's profile picture version in Unix milliseconds, 0
// when there is none or it can't be read; a missing cache-buster only costs
// the app a refetch.
func avatarVersion(dataDir string, userID int64) int64 {
	if dataDir == "" {
		return 0
	}
	stat, err := avatarutil.Stat(avatarutil.StatParams{DataDir: dataDir, UserID: userID})
	if err != nil || !stat.Exists {
		return 0
	}
	return stat.UpdatedAt.UnixMilli()
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
