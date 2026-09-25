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

// authorize loads a channel and the caller's best level on it, and checks the
// caller may do something that needs required. A non-member gets
// ErrChannelNotFound, so they can't tell the channel exists. An admin may do
// anything to any channel except read what is in it, which this package never
// serves; their level is None on a channel they are not in.
func authorize(ctx context.Context, queries *db.Queries, principal accessutil.Principal, channelID int64, required accessutil.Level) (db.ChatChannel, accessutil.Level, error) {
	channel, err := queries.GetChatChannel(ctx, channelID)
	if errors.Is(err, sql.ErrNoRows) {
		return db.ChatChannel{}, accessutil.None, ErrChannelNotFound
	}
	if err != nil {
		return db.ChatChannel{}, accessutil.None, err
	}
	level := accessutil.None
	if principal.UserID != 0 {
		rank, err := queries.GetChatChannelLevelForUser(ctx, db.GetChatChannelLevelForUserParams{
			ChannelID: channelID,
			UserID:    sql.NullInt64{Int64: principal.UserID, Valid: true},
		})
		if err != nil {
			return db.ChatChannel{}, accessutil.None, err
		}
		level = accessutil.Level(rank)
	}
	switch {
	case principal.IsAdmin || level >= required:
		return channel, level, nil
	case level == accessutil.None:
		return db.ChatChannel{}, accessutil.None, ErrChannelNotFound
	default:
		return db.ChatChannel{}, accessutil.None, ErrForbidden
	}
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

// channelFromRow is a channel as a caller with level sees it.
func channelFromRow(row db.ChatChannel, level accessutil.Level, private bool) Channel {
	return Channel{
		ID:        row.ID,
		ServerID:  row.ServerID,
		Kind:      row.Kind,
		Name:      row.Name,
		Topic:     row.Topic,
		IsDefault: row.IsDefault != 0,
		IsPrivate: private,
		Level:     level.String(),
		CreatedBy: row.CreatedBy.Int64,
		CreatedAt: row.CreatedAt,
	}
}

// memberIDs lists the active accounts a channel's rows reach.
func memberIDs(ctx context.Context, queries *db.Queries, channelID int64) ([]int64, error) {
	rows, err := queries.ListChatChannelMemberUsers(ctx, channelID)
	if err != nil {
		return nil, err
	}
	ids := make([]int64, 0, len(rows))
	for _, row := range rows {
		ids = append(ids, row.ID)
	}
	return ids, nil
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
			UserID:  row.UserID.Int64,
			GroupID: row.GroupID.Int64,
			Name:    row.Name,
			Builtin: row.Builtin != 0,
			Level:   row.Level,
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
