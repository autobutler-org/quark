package chatutil

import (
	"context"
	"database/sql"
	"encoding/json"
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

// afterMembershipChange records the change as a channel event, tells everyone
// who was or now is a member, and returns the members as they now stand.
func afterMembershipChange(ctx context.Context, queries *db.Queries, bus *eventbus.Bus, channelID int64, before []int64, dataDir string,
	kind string, actor int64, payload memberEventPayload) (ListMembersResult, error) {
	after, err := memberIDs(ctx, queries, channelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	event, err := recordEvent(ctx, queries, channelID, kind, actor, payload)
	if err != nil {
		return ListMembersResult{}, err
	}
	publish(bus, channelID, append(before, after...))
	result, err := listMembers(ctx, queries, channelID, dataDir)
	result.Event = &event
	return result, err
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

// keepingAnOwner runs change in one transaction and rolls it back with
// ErrLastOwner when it takes away the channel's last owner. Admins may do that,
// since they can manage an ownerless channel, and a channel that had no owner
// before the change is left to them too.
func keepingAnOwner(ctx context.Context, database *db.DatabaseSqlc, principal accessutil.Principal, channelID int64, change func(*db.Queries) error) error {
	return inTx(ctx, database, func(q *db.Queries) error {
		if principal.IsAdmin {
			return change(q)
		}
		before, err := ownerCount(ctx, q, channelID)
		if err != nil {
			return err
		}
		if err := change(q); err != nil {
			return err
		}
		after, err := ownerCount(ctx, q, channelID)
		if err == nil && before > 0 && after == 0 {
			return ErrLastOwner
		}
		return err
	})
}

// ownerCount is how many active accounts own a channel, directly or through a
// group.
func ownerCount(ctx context.Context, queries *db.Queries, channelID int64) (int, error) {
	rows, err := queries.ListChatChannelMemberUsers(ctx, channelID)
	count := 0
	for _, row := range rows {
		if accessutil.Level(row.LevelRank) == accessutil.Owner {
			count++
		}
	}
	return count, err
}

// keysFromRow maps a user_chat_keys row to the Keys the API serves.
func keysFromRow(row db.UserChatKey) Keys {
	return Keys{
		BoxPublicKey:      row.BoxPublicKey,
		SignPublicKey:     row.SignPublicKey,
		WrappedByPassword: row.WrappedByPassword,
		SaltPw:            row.SaltPw,
		WrappedByPhrase:   row.WrappedByPhrase,
		SaltRp:            row.SaltRp,
		KdfParams:         json.RawMessage(row.KdfParams),
		CreatedAt:         row.CreatedAt,
		UpdatedAt:         row.UpdatedAt,
	}
}

// requireMember checks the caller is a member of the channel. Admins get no
// pass here: grants, events and messages are for members, and anyone else gets
// ErrChannelNotFound.
func requireMember(ctx context.Context, queries *db.Queries, principal accessutil.Principal, channelID int64) error {
	_, err := memberLevel(ctx, queries, principal, channelID)
	return err
}

// memberLevel is the caller's best level on a channel they are a member of,
// read at least; anyone else, admins included, gets ErrChannelNotFound.
func memberLevel(ctx context.Context, queries *db.Queries, principal accessutil.Principal, channelID int64) (accessutil.Level, error) {
	if principal.UserID == 0 {
		return accessutil.None, ErrChannelNotFound
	}
	rank, err := queries.GetChatChannelLevelForUser(ctx, db.GetChatChannelLevelForUserParams{
		ChannelID: channelID,
		UserID:    sql.NullInt64{Int64: principal.UserID, Valid: true},
	})
	if err != nil {
		return accessutil.None, err
	}
	if accessutil.Level(rank) < accessutil.Read {
		return accessutil.None, ErrChannelNotFound
	}
	return accessutil.Level(rank), nil
}

// callerSignKey is the caller's published Ed25519 key, or ErrKeysNotFound.
func callerSignKey(ctx context.Context, queries *db.Queries, principal accessutil.Principal) ([]byte, error) {
	row, err := queries.GetUserChatPublicKeys(ctx, principal.UserID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrKeysNotFound
	}
	if err != nil {
		return nil, err
	}
	return row.SignPublicKey, nil
}

// validGrant checks a sealed key and signature have the sizes they must.
func validGrant(sealedKey, signature []byte) bool {
	return len(sealedKey) == SealedKeyBytes && len(signature) == SignatureBytes
}

// loadKeyState reads a channel's versions, members and grants.
func loadKeyState(ctx context.Context, queries *db.Queries, channelID int64) (keyState, error) {
	keys, err := queries.ListChatChannelKeys(ctx, channelID)
	if err != nil {
		return keyState{}, err
	}
	memberRows, err := queries.ListChatChannelMemberUsers(ctx, channelID)
	if err != nil {
		return keyState{}, err
	}
	published, err := queries.ListActiveUserChatPublicKeys(ctx)
	if err != nil {
		return keyState{}, err
	}
	recipients, err := queries.ListChatKeyGrantRecipients(ctx, channelID)
	if err != nil {
		return keyState{}, err
	}
	state := keyState{
		versions: make([]KeyVersion, 0, len(keys)),
		members:  map[int64]bool{},
		boxKeys:  map[int64][]byte{},
		holders:  map[int64]map[int64]bool{},
	}
	for _, key := range keys {
		state.versions = append(state.versions, versionFromRow(key))
		state.current = max(state.current, key.Version)
		state.holders[key.Version] = map[int64]bool{}
	}
	for _, row := range memberRows {
		state.members[row.ID] = true
	}
	for _, row := range published {
		if state.members[row.UserID] {
			state.boxKeys[row.UserID] = row.BoxPublicKey
		}
	}
	for _, row := range recipients {
		if row.Version == state.current && (!row.UserID.Valid || !state.members[row.UserID.Int64]) {
			state.strangers = true
		}
		if row.UserID.Valid && state.members[row.UserID.Int64] {
			state.holders[row.Version][row.UserID.Int64] = true
		}
	}
	return state, nil
}

// notifyChannel publishes chat_key_needed for one channel when it has pending
// grants or needs rotating, and reports whether it did.
func notifyChannel(ctx context.Context, queries *db.Queries, bus *eventbus.Bus, channelID int64) (bool, error) {
	state, err := loadKeyState(ctx, queries, channelID)
	if err != nil {
		return false, err
	}
	if !state.rotationNeeded() && len(state.pending()) == 0 {
		return false, nil
	}
	holders := state.keyHolders()
	if len(holders) == 0 {
		return false, nil
	}
	publishTo(bus, eventbus.EventChatKeyNeeded, channelID, holders)
	return true, nil
}

// insertGrant stores a grant unless the recipient already has that version,
// and returns whichever is stored.
func insertGrant(ctx context.Context, queries *db.Queries, channelID int64, g GrantUpload, granter int64, signKey []byte) (db.ChatKeyGrant, error) {
	recipient := sql.NullInt64{Int64: g.UserID, Valid: true}
	err := queries.InsertChatKeyGrant(ctx, db.InsertChatKeyGrantParams{
		ChannelID:      channelID,
		Version:        g.Version,
		UserID:         recipient,
		SealedKey:      g.SealedKey,
		GrantedBy:      sql.NullInt64{Int64: granter, Valid: true},
		GranterSignKey: signKey,
		Signature:      g.Signature,
	})
	if err != nil {
		return db.ChatKeyGrant{}, err
	}
	return queries.GetChatKeyGrant(ctx, db.GetChatKeyGrantParams{ChannelID: channelID, Version: g.Version, UserID: recipient})
}

// recordEvent writes a system event with a JSON payload, for the actor to
// sign.
func recordEvent(ctx context.Context, queries *db.Queries, channelID int64, kind string, actor int64, payload any) (ChannelEvent, error) {
	text, err := json.Marshal(payload)
	if err != nil {
		return ChannelEvent{}, err
	}
	row, err := queries.CreateChatChannelEvent(ctx, db.CreateChatChannelEventParams{
		ChannelID: channelID,
		Kind:      kind,
		ActorID:   sql.NullInt64{Int64: actor, Valid: actor != 0},
		Payload:   string(text),
	})
	if err != nil {
		return ChannelEvent{}, err
	}
	return eventFromRow(row), nil
}

// memberPayload describes the account or group a member event is about.
func memberPayload(ctx context.Context, queries *db.Queries, userID, groupID int64, level string) (memberEventPayload, error) {
	payload := memberEventPayload{UserID: userID, GroupID: groupID, Level: level}
	if userID != 0 {
		user, err := queries.GetUserByID(ctx, userID)
		if err != nil {
			return payload, err
		}
		payload.Name = user.Username
		return payload, nil
	}
	group, err := queries.GetGroup(ctx, groupID)
	if err != nil {
		return payload, err
	}
	payload.Name = group.Name
	return payload, nil
}

// publishTo sends a chat event carrying a channel id to an audience.
func publishTo(bus *eventbus.Bus, kind eventbus.EventKind, channelID int64, audience []int64) {
	if bus == nil || len(audience) == 0 {
		return
	}
	bus.Publish(eventbus.Event{Kind: kind, Data: eventbus.ChatChannelChanged{ChannelID: channelID, Audience: audience}})
}

// versionFromRow maps a chat_channel_keys row.
func versionFromRow(row db.ChatChannelKey) KeyVersion {
	return KeyVersion{Version: row.Version, CreatedBy: row.CreatedBy.Int64, CreatedAt: row.CreatedAt}
}

// grantFromRow maps a chat_key_grants row.
func grantFromRow(row db.ChatKeyGrant) KeyGrant {
	return KeyGrant{
		Version:        row.Version,
		UserID:         row.UserID.Int64,
		SealedKey:      row.SealedKey,
		GrantedBy:      row.GrantedBy.Int64,
		GranterSignKey: row.GranterSignKey,
		Signature:      row.Signature,
		CreatedAt:      row.CreatedAt,
	}
}

// eventFromRow maps a chat_channel_events row.
func eventFromRow(row db.ChatChannelEvent) ChannelEvent {
	return ChannelEvent{
		ID:            row.ID,
		ChannelID:     row.ChannelID,
		Kind:          row.Kind,
		ActorID:       row.ActorID.Int64,
		Payload:       row.Payload,
		Signature:     row.Signature,
		SignerSignKey: row.SignerSignKey,
		CreatedAt:     row.CreatedAt,
	}
}

// messageFromRow maps a chat_messages row.
func messageFromRow(row db.ChatMessage) Message {
	message := Message{
		ID:         row.ID,
		ChannelID:  row.ChannelID,
		AuthorID:   row.AuthorID.Int64,
		KeyVersion: row.KeyVersion,
		Ciphertext: row.Ciphertext,
		CreatedAt:  row.CreatedAt,
	}
	if row.EditedAt.Valid {
		message.EditedAt = &row.EditedAt.Time
	}
	if row.DeletedAt.Valid {
		message.DeletedAt = &row.DeletedAt.Time
	}
	return message
}

// publishMessage tells a channel's members about a message: the whole row
// when it was created, only its id when deleted.
func publishMessage(ctx context.Context, queries *db.Queries, bus *eventbus.Bus, kind eventbus.EventKind, message Message) error {
	if bus == nil {
		return nil
	}
	audience, err := memberIDs(ctx, queries, message.ChannelID)
	if err != nil {
		return err
	}
	data := eventbus.ChatMessageChanged{ChannelID: message.ChannelID, MessageID: message.ID, Audience: audience}
	if kind == eventbus.EventChatMessageCreated {
		data.Message = message
	}
	bus.Publish(eventbus.Event{Kind: kind, Data: data})
	return nil
}
