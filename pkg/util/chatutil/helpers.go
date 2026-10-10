package chatutil

import (
	"bytes"
	"cmp"
	"context"
	"crypto/ed25519"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"slices"
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

// afterMembershipChange records the change as a channel event, tells everyone
// who was or now is a member, asks the key holders to fill a newcomer's grants
// or rotate, and returns the members as they now stand. The ask goes out here
// rather than waiting on WatchKeyNeeds (#2624), which stays as the fallback
// for changes that don't come through SetMember or RemoveMember.
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
	// The change is committed: a failure here leaves the grant to the watcher
	// or the next client to open the channel, not the request.
	if _, err := notifyChannel(ctx, queries, bus, channelID); err != nil {
		log.Printf("[chatutil] key needs for channel %d: %v", channelID, err)
	}
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

// keepingAnOwner runs change in one transaction and rolls it back with
// ErrLastOwner when it takes away the channel's last holder of manage_channel
// while other members remain (#2422). Admins may do that, since they can
// manage such a channel, and a channel that had no holder before the change
// is left to them too.
func keepingAnOwner(ctx context.Context, database *db.DatabaseSqlc, principal accessutil.Principal, channelID int64, change func(*db.Queries) error) error {
	return inTx(ctx, database, func(q *db.Queries) error {
		if principal.IsAdmin {
			return change(q)
		}
		before, _, err := ownerCount(ctx, q, channelID)
		if err != nil {
			return err
		}
		if err := change(q); err != nil {
			return err
		}
		after, members, err := ownerCount(ctx, q, channelID)
		if err == nil && before > 0 && after == 0 && members > 0 {
			return ErrLastOwner
		}
		return err
	})
}

// ownerCount is how many active accounts hold manage_channel on a channel,
// directly or through a group, out of how many members it has.
func ownerCount(ctx context.Context, queries *db.Queries, channelID int64) (int, int, error) {
	users, err := memberUsers(ctx, queries, channelID)
	count := 0
	for _, user := range users {
		if user.Perms.Has(PermManageChannel) {
			count++
		}
	}
	return count, len(users), err
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

// requireMember checks the caller is in the conversation: holds
// read_messages on the channel. Admins get no pass here: grants, events and
// messages are for members, and anyone else, a delegated manager included,
// gets ErrChannelNotFound.
func requireMember(ctx context.Context, queries *db.Queries, principal accessutil.Principal, channelID int64) error {
	_, err := memberPerms(ctx, queries, principal, channelID)
	return err
}

// memberPerms is the caller's effective set on a channel they read, which
// holds read_messages; anyone else, delegated managers and admins included,
// gets ErrChannelNotFound.
func memberPerms(ctx context.Context, queries *db.Queries, principal accessutil.Principal, channelID int64) (Perms, error) {
	perms, err := resolvePerms(ctx, queries, channelID, principal.UserID)
	if err != nil {
		return 0, err
	}
	if !perms.Has(PermReadMessages) {
		return 0, ErrChannelNotFound
	}
	return perms, nil
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

// grantSigned checks a grant's signature against the granter's published
// signing key, over GrantMessage (#2486). The recipient still verifies; this
// keeps garbage out of the table and off the event bus.
func grantSigned(signKey []byte, channelID int64, g GrantUpload) bool {
	if len(signKey) != ed25519.PublicKeySize || len(g.Signature) != ed25519.SignatureSize {
		return false
	}
	return ed25519.Verify(signKey, GrantMessage(channelID, g.Version, g.UserID, g.SealedKey), g.Signature)
}

// loadKeyState reads a channel's versions, members and grants.
func loadKeyState(ctx context.Context, queries *db.Queries, channelID int64) (keyState, error) {
	keys, err := queries.ListChatChannelKeys(ctx, channelID)
	if err != nil {
		return keyState{}, err
	}
	users, err := memberUsers(ctx, queries, channelID)
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
	// Only read_messages entitles a key (#2417): a delegated manager is never
	// pending, and losing read_messages makes a holder a stranger, which
	// rotates the key.
	for _, user := range users {
		if user.Perms.Has(PermReadMessages) {
			state.members[user.UserID] = true
		}
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
func memberPayload(ctx context.Context, queries *db.Queries, userID, groupID int64, perms Perms) (memberEventPayload, error) {
	payload := memberEventPayload{UserID: userID, GroupID: groupID, Permissions: perms}
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

// publishMessage tells a channel's readers about a message: the whole row
// when it was created, only its id when deleted.
func publishMessage(ctx context.Context, queries *db.Queries, bus *eventbus.Bus, kind eventbus.EventKind, message Message) error {
	if bus == nil {
		return nil
	}
	audience, err := readers(ctx, queries, message.ChannelID)
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

// readers is the accounts holding read_messages on a channel, the audience of
// anything carrying ciphertext: never a delegated manager (#2418).
func readers(ctx context.Context, queries *db.Queries, channelID int64) ([]int64, error) {
	users, err := memberUsers(ctx, queries, channelID)
	if err != nil {
		return nil, err
	}
	audience := []int64{}
	for _, user := range users {
		if user.Perms.Has(PermReadMessages) {
			audience = append(audience, user.UserID)
		}
	}
	return audience, nil
}

// unreadCounts is an account's unread count in each channel that has one:
// the messages after its read marker that someone else wrote and nobody
// deleted. It covers every channel, readable or not; callers keep only the
// channels the account reads.
func unreadCounts(ctx context.Context, queries *db.Queries, userID int64) (map[int64]int64, error) {
	rows, err := queries.CountChatUnreadForUser(ctx, userID)
	counts := make(map[int64]int64, len(rows))
	for _, row := range rows {
		counts[row.ChannelID] = row.Unread
	}
	return counts, err
}

// attachUnread sets UnreadCount on each channel the account reads.
func attachUnread(ctx context.Context, queries *db.Queries, userID int64, channels []Channel) error {
	unread, err := unreadCounts(ctx, queries, userID)
	if err != nil {
		return err
	}
	for i := range channels {
		if channels[i].Permissions.Has(PermReadMessages) {
			channels[i].UnreadCount = unread[channels[i].ID]
		}
	}
	return nil
}

// readableMessage is a message and the caller's set on its channel, or
// ErrMessageNotFound when either the message doesn't exist or the caller
// doesn't hold read_messages there.
func readableMessage(ctx context.Context, queries *db.Queries, principal accessutil.Principal, messageID int64) (db.ChatMessage, Perms, error) {
	message, err := queries.GetChatMessage(ctx, messageID)
	if errors.Is(err, sql.ErrNoRows) {
		return db.ChatMessage{}, 0, ErrMessageNotFound
	}
	if err != nil {
		return db.ChatMessage{}, 0, err
	}
	perms, err := memberPerms(ctx, queries, principal, message.ChannelID)
	if errors.Is(err, ErrChannelNotFound) {
		return db.ChatMessage{}, 0, ErrMessageNotFound
	}
	return message, perms, err
}

func reactionFromRow(row db.ChatReaction) Reaction {
	return Reaction{
		ID:         row.ID,
		MessageID:  row.MessageID,
		UserID:     row.UserID,
		KeyVersion: row.KeyVersion,
		Ciphertext: row.Ciphertext,
		CreatedAt:  row.CreatedAt,
	}
}

// attachReactions fills in the reactions of messages, one page of a
// channel's messages sorted by id.
func attachReactions(ctx context.Context, queries *db.Queries, channelID int64, messages []Message) error {
	if len(messages) == 0 {
		return nil
	}
	rows, err := queries.ListChatReactionsBetween(ctx, db.ListChatReactionsBetweenParams{
		ChannelID: channelID, FirstID: messages[0].ID, LastID: messages[len(messages)-1].ID,
	})
	if err != nil {
		return err
	}
	for _, row := range rows {
		i, found := slices.BinarySearchFunc(messages, row.MessageID, func(m Message, id int64) int { return cmp.Compare(m.ID, id) })
		if found {
			messages[i].Reactions = append(messages[i].Reactions, reactionFromRow(row))
		}
	}
	return nil
}

// publishReaction tells a channel's readers a reaction on messageID was added,
// with the stored row, or removed, with reaction nil.
func publishReaction(ctx context.Context, queries *db.Queries, bus *eventbus.Bus, channelID, messageID, reactionID int64, reaction *Reaction) error {
	if bus == nil {
		return nil
	}
	audience, err := readers(ctx, queries, channelID)
	if err != nil {
		return err
	}
	data := eventbus.ChatReactionChanged{ChannelID: channelID, MessageID: messageID, ReactionID: reactionID, Audience: audience}
	if reaction != nil {
		data.Reaction = *reaction
	}
	bus.Publish(eventbus.Event{Kind: eventbus.EventChatReactionChanged, Data: data})
	return nil
}

// repeatedPost answers a post whose nonce the channel already holds under its
// key version. The caller's own live message with the same ciphertext is a
// retry and comes back as it is; anything else is a replay.
func repeatedPost(params PostMessageParams) (PostMessageResult, error) {
	row, err := params.Database.Queries.GetChatMessageByNonce(params.Ctx, db.GetChatMessageByNonceParams{
		ChannelID: params.ChannelID, KeyVersion: params.KeyVersion, Nonce: params.Ciphertext[:NonceBytes],
	})
	if err != nil {
		return PostMessageResult{}, err
	}
	if row.AuthorID.Int64 != params.Principal.UserID || !bytes.Equal(row.Ciphertext, params.Ciphertext) {
		return PostMessageResult{}, ErrDuplicateMessage
	}
	return PostMessageResult{Message: messageFromRow(row), Repeated: true}, nil
}
