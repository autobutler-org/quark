// Package chatutil manages chat channels and who belongs to them (#2415).
//
// A Quark hosts one chat server, and the server has channels. A channel's
// members are rows naming one account or one group at read, write or owner,
// the same shape as path_access: membership is additive, the best level wins,
// and the built-in everyone group reaches every active account. general is
// seeded with a write row for everyone, can't be deleted, and can't lose that
// row.
//
// Admins do not bypass membership: a channel they are not in never appears in
// their list, because its content is end-to-end encrypted and they could not
// read it anyway. They may still manage any channel: rename or delete it, and
// list or change its members. read sees a channel, write also posts, and owner
// also manages it. Any active account may create a channel and owns it.
//
// Every change publishes chat_channel_changed to the channel's members, before
// and after the change; accessutil.FilterEvent keeps it from everyone else.
//
// Channel keys (#2417) are made and shared by clients, never the Quark. A
// channel has key versions; a member holds a version through a grant, the key
// sealed to their X25519 key and signed by whoever granted it. The Quark works
// out who is missing a grant (members with published keys lacking a version)
// and whether the key needs rotating (someone outside the channel holds the
// current version), and tells the members who can act with chat_key_needed.
// Membership and key changes are also recorded as channel events, which the
// actor's client signs.
//
// Messages (#2418) are ciphertext under a channel key version; the Quark
// stores, pages and tombstones them and never opens one. Posting and deleting
// publish chat_message_created and chat_message_deleted to the channel's
// members alone: admins who aren't members hear neither, and like everyone
// outside a channel get ErrChannelNotFound for its messages.
package chatutil

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"slices"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

// MaxNameLength and MaxTopicLength cap a channel's name and topic, in
// characters.
const (
	MaxNameLength  = 64
	MaxTopicLength = 512
)

// The sentinels' text is written for the app to show, so handlers send it out
// unwrapped. Grants reuse accessutil's ErrGrantTarget, ErrPrincipalNotFound and
// ErrInvalidLevel.
var (
	// ErrChannelNotFound reports a channel that doesn't exist or that the
	// caller may not see, so a non-member can't learn a channel's name.
	ErrChannelNotFound = errors.New("no channel has that id")
	// ErrForbidden reports a member who isn't an owner changing the channel.
	ErrForbidden = errors.New("only an owner of the channel or an admin can change it")
	// ErrInvalidName reports a name that is empty, too long, or holds a
	// control character once trimmed.
	ErrInvalidName = errors.New("a channel name has 1 to 64 characters and no line breaks or tabs")
	// ErrInvalidTopic reports a topic that is too long.
	ErrInvalidTopic = errors.New("a channel topic has at most 512 characters")
	// ErrNameTaken reports a name another channel already has, ignoring case.
	ErrNameTaken = errors.New("a channel with that name already exists")
	// ErrDefaultChannel reports deleting general.
	ErrDefaultChannel = errors.New("the general channel can't be deleted")
	// ErrDefaultEveryone reports removing everyone from general.
	ErrDefaultEveryone = errors.New("everyone can't be removed from the general channel")
	// ErrMemberNotFound reports removing an account or group that has no row
	// on the channel.
	ErrMemberNotFound = errors.New("that account or group isn't a member of this channel")
)

// Channel is one channel as the caller sees it.
type Channel struct {
	ID       int64 `json:"id"`
	ServerID int64 `json:"serverId"`
	// Kind is channel; dm is reserved for direct messages (#2423).
	Kind  string `json:"kind"`
	Name  string `json:"name"`
	Topic string `json:"topic"`
	// IsDefault marks general.
	IsDefault bool `json:"isDefault"`
	// IsPrivate is whether everyone has no row on the channel.
	IsPrivate bool `json:"isPrivate"`
	// Level is the caller's best level: read, write or owner. It is empty for
	// an admin managing a channel they are not a member of.
	Level string `json:"level,omitempty"`
	// CreatedBy is the account that created the channel; absent for general
	// and for a channel whose creator was deleted.
	CreatedBy int64     `json:"createdBy,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

// Member is one row on a channel: an account or a group.
type Member struct {
	// UserID is set for an account.
	UserID int64 `json:"userId,omitempty"`
	// GroupID is set for a group.
	GroupID int64 `json:"groupId,omitempty"`
	// Name is the account's username or the group's name.
	Name string `json:"name"`
	// Builtin marks the everyone group.
	Builtin bool `json:"builtin"`
	// Level is read, write or owner.
	Level string `json:"level"`
	// AvatarUpdatedAt is an account's profile picture version in Unix
	// milliseconds, absent when it has none.
	AvatarUpdatedAt int64 `json:"avatarUpdatedAt,omitempty"`
	// Users are the active accounts in a group, everyone's being every active
	// account. Absent for an account or an empty group.
	Users []MemberUser `json:"users,omitempty"`
}

// MemberUser is an account inside a group row.
type MemberUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	// AvatarUpdatedAt is the profile picture version in Unix milliseconds,
	// absent when it has none.
	AvatarUpdatedAt int64 `json:"avatarUpdatedAt,omitempty"`
}

// ResolvedUser is an active account a channel's rows reach, with its best
// level.
type ResolvedUser struct {
	UserID   int64
	Username string
	Level    accessutil.Level
}

// ListChannelsParams asks for the caller's channels.
type ListChannelsParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
}

// ListChannelsResult is the caller's channels, general first, then by name.
type ListChannelsResult struct {
	Channels []Channel `json:"channels"`
}

// ListChannels lists the channels the caller is a member of, directly, through
// a group, or through everyone, with the caller's best level on each. Admins
// get only their own channels too.
func ListChannels(params ListChannelsParams) (ListChannelsResult, error) {
	if params.Database == nil {
		return ListChannelsResult{}, accessutil.ErrNoDatabase
	}
	rows, err := params.Database.Queries.ListChatChannelsForUser(params.Ctx,
		sql.NullInt64{Int64: params.Principal.UserID, Valid: true})
	if err != nil {
		return ListChannelsResult{}, err
	}
	channels := make([]Channel, 0, len(rows))
	for _, row := range rows {
		channels = append(channels, Channel{
			ID:        row.ID,
			ServerID:  row.ServerID,
			Kind:      row.Kind,
			Name:      row.Name,
			Topic:     row.Topic,
			IsDefault: row.IsDefault != 0,
			IsPrivate: row.IsPrivate != 0,
			Level:     accessutil.Level(row.LevelRank).String(),
			CreatedBy: row.CreatedBy.Int64,
			CreatedAt: row.CreatedAt,
		})
	}
	return ListChannelsResult{Channels: channels}, nil
}

// CreateChannelParams creates a channel owned by the caller.
type CreateChannelParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	Name      string
	Topic     string
}

// CreateChannelResult is the new channel.
type CreateChannelResult struct {
	Channel Channel
}

// CreateChannel creates a private channel on the Quark's server and makes the
// caller its owner. The name is trimmed and must be unique ignoring case
// (ErrNameTaken).
func CreateChannel(params CreateChannelParams) (CreateChannelResult, error) {
	name, topic, err := validate(params.Name, params.Topic)
	if err != nil {
		return CreateChannelResult{}, err
	}
	if params.Database == nil {
		return CreateChannelResult{}, accessutil.ErrNoDatabase
	}
	if params.Principal.UserID == 0 {
		return CreateChannelResult{}, accessutil.ErrPrincipalNotFound
	}
	creator := sql.NullInt64{Int64: params.Principal.UserID, Valid: true}
	var row db.ChatChannel
	err = inTx(params.Ctx, params.Database, func(q *db.Queries) error {
		var err error
		row, err = q.CreateChatChannel(params.Ctx, db.CreateChatChannelParams{Name: name, Topic: topic, CreatedBy: creator})
		if err != nil {
			return err
		}
		return q.SetChatChannelUserMember(params.Ctx, db.SetChatChannelUserMemberParams{
			ChannelID: row.ID, UserID: creator, Level: accessutil.Owner.String(),
		})
	})
	if sqlutil.IsUniqueConstraintErr(err) {
		return CreateChannelResult{}, ErrNameTaken
	}
	if err != nil {
		return CreateChannelResult{}, err
	}
	publish(params.EventBus, row.ID, []int64{params.Principal.UserID})
	return CreateChannelResult{Channel: channelFromRow(row, accessutil.Owner, true)}, nil
}

// UpdateChannelParams renames a channel or changes its topic. A nil field is
// left as it is.
type UpdateChannelParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	Name      *string
	Topic     *string
}

// UpdateChannelResult is the channel as it now stands.
type UpdateChannelResult struct {
	Channel Channel
}

// UpdateChannel renames a channel or changes its topic, for an owner of it or
// an admin. A non-member who isn't an admin gets ErrChannelNotFound, and a
// member who isn't an owner ErrForbidden.
func UpdateChannel(params UpdateChannelParams) (UpdateChannelResult, error) {
	if params.Database == nil {
		return UpdateChannelResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	current, level, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, accessutil.Owner)
	if err != nil {
		return UpdateChannelResult{}, err
	}
	name, topic := current.Name, current.Topic
	if params.Name != nil {
		name = *params.Name
	}
	if params.Topic != nil {
		topic = *params.Topic
	}
	if name, topic, err = validate(name, topic); err != nil {
		return UpdateChannelResult{}, err
	}
	audience, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return UpdateChannelResult{}, err
	}
	row, err := queries.UpdateChatChannel(params.Ctx, db.UpdateChatChannelParams{ID: params.ChannelID, Name: name, Topic: topic})
	if sqlutil.IsUniqueConstraintErr(err) {
		return UpdateChannelResult{}, ErrNameTaken
	}
	if err != nil {
		return UpdateChannelResult{}, err
	}
	private, err := isPrivate(params.Ctx, queries, row.ID)
	if err != nil {
		return UpdateChannelResult{}, err
	}
	publish(params.EventBus, row.ID, audience)
	return UpdateChannelResult{Channel: channelFromRow(row, level, private)}, nil
}

// DeleteChannelParams deletes a channel.
type DeleteChannelParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
}

// DeleteChannelResult reports the deleted channel.
type DeleteChannelResult struct {
	ChannelID int64
}

// DeleteChannel deletes a channel and its members, for an owner of it or an
// admin. general can't be deleted (ErrDefaultChannel). Access errors are
// UpdateChannel's.
func DeleteChannel(params DeleteChannelParams) (DeleteChannelResult, error) {
	if params.Database == nil {
		return DeleteChannelResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	current, _, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, accessutil.Owner)
	if err != nil {
		return DeleteChannelResult{}, err
	}
	if current.IsDefault != 0 {
		return DeleteChannelResult{}, ErrDefaultChannel
	}
	audience, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return DeleteChannelResult{}, err
	}
	if _, err := queries.DeleteChatChannel(params.Ctx, params.ChannelID); err != nil {
		return DeleteChannelResult{}, err
	}
	publish(params.EventBus, params.ChannelID, audience)
	return DeleteChannelResult{ChannelID: params.ChannelID}, nil
}

// ListMembersParams asks who belongs to a channel.
type ListMembersParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	ChannelID int64
	// DataDir is the Quark's data directory, where profile pictures are
	// (storageutil.GetDataDir).
	DataDir string
}

// ListMembersResult is a channel's rows: groups first, then accounts, each by
// name.
type ListMembersResult struct {
	Members []Member `json:"members"`
	// Event is the member_set or member_removed event SetMember and
	// RemoveMember recorded, for the caller to sign; absent from ListMembers.
	Event *ChannelEvent `json:"event,omitempty"`
}

// ListMembers lists a channel's rows, each group with the active accounts in
// it, for any member of the channel or an admin. Anyone else gets
// ErrChannelNotFound.
func ListMembers(params ListMembersParams) (ListMembersResult, error) {
	if params.Database == nil {
		return ListMembersResult{}, accessutil.ErrNoDatabase
	}
	if _, _, err := authorize(params.Ctx, params.Database.Queries, params.Principal, params.ChannelID, accessutil.Read); err != nil {
		return ListMembersResult{}, err
	}
	return listMembers(params.Ctx, params.Database.Queries, params.ChannelID, params.DataDir)
}

// SetMemberParams gives one account or group a level on a channel. Exactly
// one of UserID and GroupID is set.
type SetMemberParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	UserID    int64
	GroupID   int64
	Level     accessutil.Level
	// DataDir is where profile pictures are, for the returned members.
	DataDir string
}

// SetMember adds an account or group to a channel, or changes its level, and
// returns the channel's members as they now stand. It answers to an owner of
// the channel or an admin; access errors are UpdateChannel's. The account must
// be active and the group must exist (accessutil.ErrPrincipalNotFound).
func SetMember(params SetMemberParams) (ListMembersResult, error) {
	if (params.UserID == 0) == (params.GroupID == 0) {
		return ListMembersResult{}, accessutil.ErrGrantTarget
	}
	if params.Level < accessutil.Read || params.Level > accessutil.Owner {
		return ListMembersResult{}, accessutil.ErrInvalidLevel
	}
	if params.Database == nil {
		return ListMembersResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if _, _, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, accessutil.Owner); err != nil {
		return ListMembersResult{}, err
	}
	if err := ensurePrincipal(params.Ctx, queries, params.UserID, params.GroupID); err != nil {
		return ListMembersResult{}, err
	}
	before, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	if params.UserID != 0 {
		err = queries.SetChatChannelUserMember(params.Ctx, db.SetChatChannelUserMemberParams{
			ChannelID: params.ChannelID,
			UserID:    sql.NullInt64{Int64: params.UserID, Valid: true},
			Level:     params.Level.String(),
		})
	} else {
		err = queries.SetChatChannelGroupMember(params.Ctx, db.SetChatChannelGroupMemberParams{
			ChannelID: params.ChannelID,
			GroupID:   sql.NullInt64{Int64: params.GroupID, Valid: true},
			Level:     params.Level.String(),
		})
	}
	if err != nil {
		return ListMembersResult{}, err
	}
	payload, err := memberPayload(params.Ctx, queries, params.UserID, params.GroupID, params.Level.String())
	if err != nil {
		return ListMembersResult{}, err
	}
	return afterMembershipChange(params.Ctx, queries, params.EventBus, params.ChannelID, before, params.DataDir,
		EventMemberSet, params.Principal.UserID, payload)
}

// RemoveMemberParams removes one account's or group's row from a channel.
// Exactly one of UserID and GroupID is set.
type RemoveMemberParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	UserID    int64
	GroupID   int64
	// DataDir is where profile pictures are, for the returned members.
	DataDir string
}

// RemoveMember removes a row from a channel and returns the channel's members
// as they now stand. An owner or an admin may remove any row, and any member
// may remove their own account's row, which is leaving. everyone can't be
// removed from general (ErrDefaultEveryone), and a principal with no row is
// ErrMemberNotFound. Other access errors are UpdateChannel's.
func RemoveMember(params RemoveMemberParams) (ListMembersResult, error) {
	if (params.UserID == 0) == (params.GroupID == 0) {
		return ListMembersResult{}, accessutil.ErrGrantTarget
	}
	if params.Database == nil {
		return ListMembersResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	required := accessutil.Owner
	if params.UserID != 0 && params.UserID == params.Principal.UserID {
		required = accessutil.Read
	}
	current, _, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, required)
	if err != nil {
		return ListMembersResult{}, err
	}
	if current.IsDefault != 0 && params.GroupID != 0 {
		everyone, err := isEveryone(params.Ctx, queries, params.GroupID)
		if err != nil {
			return ListMembersResult{}, err
		}
		if everyone {
			return ListMembersResult{}, ErrDefaultEveryone
		}
	}
	before, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	payload, err := memberPayload(params.Ctx, queries, params.UserID, params.GroupID, "")
	if errors.Is(err, sql.ErrNoRows) {
		return ListMembersResult{}, ErrMemberNotFound
	}
	if err != nil {
		return ListMembersResult{}, err
	}
	var deleted int64
	if params.UserID != 0 {
		deleted, err = queries.DeleteChatChannelUserMember(params.Ctx, db.DeleteChatChannelUserMemberParams{
			ChannelID: params.ChannelID,
			UserID:    sql.NullInt64{Int64: params.UserID, Valid: true},
		})
	} else {
		deleted, err = queries.DeleteChatChannelGroupMember(params.Ctx, db.DeleteChatChannelGroupMemberParams{
			ChannelID: params.ChannelID,
			GroupID:   sql.NullInt64{Int64: params.GroupID, Valid: true},
		})
	}
	if err != nil {
		return ListMembersResult{}, err
	}
	if deleted == 0 {
		return ListMembersResult{}, ErrMemberNotFound
	}
	return afterMembershipChange(params.Ctx, queries, params.EventBus, params.ChannelID, before, params.DataDir,
		EventMemberRemoved, params.Principal.UserID, payload)
}

// ResolveMemberUsersParams names the channel whose members to resolve.
type ResolveMemberUsersParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	ChannelID int64
}

// ResolveMemberUsersResult is every active account the channel's rows reach.
type ResolveMemberUsersResult struct {
	Users []ResolvedUser
}

// ResolveMemberUsers expands a channel's rows into the active accounts they
// reach, directly, through a group, or through everyone, each with its best
// level, by username. It checks no caller: it is for the Quark's own use, such
// as working out who needs a channel key (#2417).
func ResolveMemberUsers(params ResolveMemberUsersParams) (ResolveMemberUsersResult, error) {
	if params.Database == nil {
		return ResolveMemberUsersResult{}, accessutil.ErrNoDatabase
	}
	rows, err := params.Database.Queries.ListChatChannelMemberUsers(params.Ctx, params.ChannelID)
	if err != nil {
		return ResolveMemberUsersResult{}, err
	}
	users := make([]ResolvedUser, 0, len(rows))
	for _, row := range rows {
		users = append(users, ResolvedUser{UserID: row.ID, Username: row.Username, Level: accessutil.Level(row.LevelRank)})
	}
	return ResolveMemberUsersResult{Users: users}, nil
}

// Sizes a stored chat identity must have (#2416). The public keys are X25519
// and Ed25519, and the salts are libsodium's crypto_pwhash_SALTBYTES. A
// wrapped key is nonce, ciphertext and tag, which the Quark can't open, so it
// is only bounded.
const (
	PublicKeyBytes      = 32
	SaltBytes           = 16
	MaxWrappedKeyBytes  = 512
	MaxKdfParamsBytes   = 512
	MaxKeysRequestBytes = 8 << 10
)

var (
	// ErrKeysNotFound reports an account with no chat identity yet, or asking
	// for the public keys of an account that doesn't exist or isn't active.
	ErrKeysNotFound = errors.New("no chat keys for that account")
	// ErrInvalidKeys reports keys of the wrong size or shape.
	ErrInvalidKeys = errors.New("chat keys have the wrong size or shape")
)

// Keys is an account's stored chat identity: its public keys, and its private
// seeds wrapped on the client under the login password and, optionally, the
// recovery phrase. The Quark stores the bytes and never opens them. Byte
// fields travel as base64.
type Keys struct {
	BoxPublicKey      []byte `json:"boxPublicKey"`
	SignPublicKey     []byte `json:"signPublicKey"`
	WrappedByPassword []byte `json:"wrappedByPassword"`
	SaltPw            []byte `json:"saltPw"`
	// WrappedByPhrase and SaltRp are both present or both absent.
	WrappedByPhrase []byte `json:"wrappedByPhrase,omitempty"`
	SaltRp          []byte `json:"saltRp,omitempty"`
	// KdfParams is the client's JSON object recording the Argon2id cost.
	KdfParams json.RawMessage `json:"kdfParams" swaggertype:"object"`
	CreatedAt time.Time       `json:"createdAt"`
	UpdatedAt time.Time       `json:"updatedAt"`
}

// PublicKeys is the half of an account's chat identity anyone signed in may
// read.
type PublicKeys struct {
	UserID        int64  `json:"userId"`
	BoxPublicKey  []byte `json:"boxPublicKey"`
	SignPublicKey []byte `json:"signPublicKey"`
}

// ValidateKeys checks the sizes and shape of keys a client sent, so a
// malformed upload is refused before anything is stored.
func ValidateKeys(keys Keys) error {
	wrapped := func(b []byte) bool { return len(b) > 0 && len(b) <= MaxWrappedKeyBytes }
	var params map[string]any
	switch {
	case len(keys.BoxPublicKey) != PublicKeyBytes, len(keys.SignPublicKey) != PublicKeyBytes,
		!wrapped(keys.WrappedByPassword), len(keys.SaltPw) != SaltBytes,
		(keys.WrappedByPhrase == nil) != (keys.SaltRp == nil),
		keys.WrappedByPhrase != nil && (!wrapped(keys.WrappedByPhrase) || len(keys.SaltRp) != SaltBytes),
		len(keys.KdfParams) > MaxKdfParamsBytes, json.Unmarshal(keys.KdfParams, &params) != nil, params == nil:
		return ErrInvalidKeys
	}
	return nil
}

// GetKeysParams asks for an account's own stored chat identity.
type GetKeysParams struct {
	Ctx     context.Context
	Queries *db.Queries
	UserID  int64
}

// GetKeysResult is the account's stored chat identity.
type GetKeysResult struct {
	Keys Keys
}

// GetKeys returns an account's own chat identity, wrapped seeds included, or
// ErrKeysNotFound. Serve it only to that account.
func GetKeys(params GetKeysParams) (GetKeysResult, error) {
	row, err := params.Queries.GetUserChatKeys(params.Ctx, params.UserID)
	if errors.Is(err, sql.ErrNoRows) {
		return GetKeysResult{}, ErrKeysNotFound
	}
	if err != nil {
		return GetKeysResult{}, err
	}
	return GetKeysResult{Keys: keysFromRow(row)}, nil
}

// PutKeysParams creates or replaces an account's chat identity. Queries may
// be a transaction's, so account recovery can store re-wrapped keys in the
// same transaction that resets the password.
type PutKeysParams struct {
	Ctx     context.Context
	Queries *db.Queries
	UserID  int64
	Keys    Keys
}

// PutKeysResult is the identity as stored.
type PutKeysResult struct {
	Keys Keys
}

// PutKeys validates and stores an account's chat identity, replacing any it
// had. A new X25519 key drops the account's key grants, which were sealed to
// the old one; call NotifyKeyNeeded afterward so members refill them.
func PutKeys(params PutKeysParams) (PutKeysResult, error) {
	if err := ValidateKeys(params.Keys); err != nil {
		return PutKeysResult{}, err
	}
	k := params.Keys
	// Grants sealed to an old X25519 key can't be opened any more, so they go
	// and the account becomes pending again: members refill them, history
	// included.
	existing, err := params.Queries.GetUserChatKeys(params.Ctx, params.UserID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return PutKeysResult{}, err
	}
	if err == nil && !bytes.Equal(existing.BoxPublicKey, k.BoxPublicKey) {
		if err := params.Queries.DeleteUserChatKeyGrants(params.Ctx, sql.NullInt64{Int64: params.UserID, Valid: true}); err != nil {
			return PutKeysResult{}, fmt.Errorf("drop chat key grants: %w", err)
		}
	}
	row, err := params.Queries.UpsertUserChatKeys(params.Ctx, db.UpsertUserChatKeysParams{
		UserID:            params.UserID,
		BoxPublicKey:      k.BoxPublicKey,
		SignPublicKey:     k.SignPublicKey,
		WrappedByPassword: k.WrappedByPassword,
		SaltPw:            k.SaltPw,
		WrappedByPhrase:   k.WrappedByPhrase,
		SaltRp:            k.SaltRp,
		KdfParams:         string(k.KdfParams),
	})
	if err != nil {
		return PutKeysResult{}, fmt.Errorf("store chat keys: %w", err)
	}
	return PutKeysResult{Keys: keysFromRow(row)}, nil
}

// GetPublicKeysParams asks for another account's public chat keys.
type GetPublicKeysParams struct {
	Ctx     context.Context
	Queries *db.Queries
	UserID  int64
}

// GetPublicKeysResult is the account's public chat keys.
type GetPublicKeysResult struct {
	PublicKeys PublicKeys
}

// GetPublicKeys returns an active account's public chat keys, and never its
// wrapped seeds, or ErrKeysNotFound.
func GetPublicKeys(params GetPublicKeysParams) (GetPublicKeysResult, error) {
	row, err := params.Queries.GetUserChatPublicKeys(params.Ctx, params.UserID)
	if errors.Is(err, sql.ErrNoRows) {
		return GetPublicKeysResult{}, ErrKeysNotFound
	}
	if err != nil {
		return GetPublicKeysResult{}, err
	}
	return GetPublicKeysResult{PublicKeys: PublicKeys{
		UserID:        row.UserID,
		BoxPublicKey:  row.BoxPublicKey,
		SignPublicKey: row.SignPublicKey,
	}}, nil
}

// Sizes a key grant must have (#2417). A sealed channel key is the 32-byte
// XChaCha20-Poly1305 key plus the 48 bytes crypto_box_seal adds; a signature is
// Ed25519's 64 bytes.
const (
	SealedKeyBytes = 80
	SignatureBytes = 64
	// MaxGrantsPerUpload bounds one UploadGrants call.
	MaxGrantsPerUpload = 256
	// MaxEventsPage is the most events ListEvents returns at once.
	MaxEventsPage = 200
	// MaxGrantsRequestBytes caps a grant upload's body.
	MaxGrantsRequestBytes = 128 << 10
)

// Event kinds a channel's system events carry.
const (
	EventMemberSet     = "member_set"
	EventMemberRemoved = "member_removed"
	EventKeyCreated    = "key_created"
)

var (
	// ErrNotHolder reports granting a key version the caller holds no grant
	// for.
	ErrNotHolder = errors.New("you don't hold that version of the channel key")
	// ErrVersionConflict reports creating a key version that isn't the next
	// one, usually because another member created it first.
	ErrVersionConflict = errors.New("another member already created that key version")
	// ErrInvalidGrant reports a grant of the wrong size, or for an account
	// that isn't a member with published chat keys.
	ErrInvalidGrant = errors.New("that key grant is malformed or names someone who can't receive it")
	// ErrEventNotFound reports an event that doesn't exist on the channel or
	// wasn't the caller's to sign.
	ErrEventNotFound = errors.New("no event with that id for you to sign")
	// ErrEventSigned reports signing an event that already has a signature.
	ErrEventSigned = errors.New("that event is already signed")
)

// KeyVersion is one version of a channel's key. The key itself never reaches
// the Quark.
type KeyVersion struct {
	Version int64 `json:"version"`
	// CreatedBy is absent when the account that created it was deleted.
	CreatedBy int64     `json:"createdBy,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
}

// KeyGrant is one version of a channel key sealed to one member. Byte fields
// travel as base64.
type KeyGrant struct {
	Version int64 `json:"version"`
	UserID  int64 `json:"userId"`
	// SealedKey is crypto_box_seal of the channel key to the member's X25519
	// key.
	SealedKey []byte `json:"sealedKey"`
	// GrantedBy is absent when the granter's account was deleted.
	GrantedBy int64 `json:"grantedBy,omitempty"`
	// GranterSignKey is the granter's published Ed25519 key when the grant was
	// uploaded, which Signature verifies against.
	GranterSignKey []byte `json:"granterSignKey"`
	// Signature is the granter's Ed25519 signature over the grant's canonical
	// bytes (docs/chat-security.md).
	Signature []byte    `json:"signature"`
	CreatedAt time.Time `json:"createdAt"`
}

// GrantUpload is one grant a client sealed and signed.
type GrantUpload struct {
	Version   int64  `json:"version"`
	UserID    int64  `json:"userId"`
	SealedKey []byte `json:"sealedKey"`
	Signature []byte `json:"signature"`
}

// PendingGrant is a member missing a version of the key, and the X25519 key to
// seal it to.
type PendingGrant struct {
	Version      int64  `json:"version"`
	UserID       int64  `json:"userId"`
	BoxPublicKey []byte `json:"boxPublicKey"`
}

// ChannelEvent is a membership or key change, shown as a system line. The
// Quark writes Payload, a JSON object; the actor's client signs it afterward
// (SignEvent), and an event without a signature is shown as unverified.
type ChannelEvent struct {
	ID        int64 `json:"id"`
	ChannelID int64 `json:"channelId"`
	// Kind is member_set, member_removed or key_created.
	Kind string `json:"kind"`
	// ActorID is who made the change; absent once that account is deleted.
	ActorID int64 `json:"actorId,omitempty"`
	// Payload is the JSON the signature covers, byte for byte: for a member
	// change {"userId"|"groupId", "name", "level"}, for a key {"version"}.
	Payload string `json:"payload"`
	// Signature and SignerSignKey are both absent until the actor signs.
	Signature     []byte    `json:"signature,omitempty"`
	SignerSignKey []byte    `json:"signerSignKey,omitempty"`
	CreatedAt     time.Time `json:"createdAt"`
}

// GetChannelKeysParams asks for a channel's key versions and the caller's own
// grants.
type GetChannelKeysParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	ChannelID int64
}

// GetChannelKeysResult is what a member needs to open a channel.
type GetChannelKeysResult struct {
	// CurrentVersion is the newest version, 0 before any exists: the first
	// member client to open the channel then creates version 1.
	CurrentVersion int64        `json:"currentVersion"`
	Versions       []KeyVersion `json:"versions"`
	// Grants are the caller's own, one per version it has been given.
	Grants []KeyGrant `json:"grants"`
	// RotationNeeded is set when someone holding the current version is no
	// longer a member; the next member client online creates the next one.
	RotationNeeded bool `json:"rotationNeeded"`
}

// GetChannelKeys returns a channel's key versions and the caller's grants,
// for members only: anyone else, admins included, gets ErrChannelNotFound.
func GetChannelKeys(params GetChannelKeysParams) (GetChannelKeysResult, error) {
	if params.Database == nil {
		return GetChannelKeysResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if err := requireMember(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return GetChannelKeysResult{}, err
	}
	state, err := loadKeyState(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return GetChannelKeysResult{}, err
	}
	rows, err := queries.ListChatKeyGrantsForUser(params.Ctx, db.ListChatKeyGrantsForUserParams{
		ChannelID: params.ChannelID, UserID: sql.NullInt64{Int64: params.Principal.UserID, Valid: true},
	})
	if err != nil {
		return GetChannelKeysResult{}, err
	}
	grants := make([]KeyGrant, 0, len(rows))
	for _, row := range rows {
		grants = append(grants, grantFromRow(row))
	}
	return GetChannelKeysResult{
		CurrentVersion: state.current,
		Versions:       state.versions,
		Grants:         grants,
		RotationNeeded: state.rotationNeeded(),
	}, nil
}

// ListPendingGrantsParams asks what grants the caller could fill.
type ListPendingGrantsParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	ChannelID int64
}

// ListPendingGrantsResult is the grants the caller can fill, by version then
// account.
type ListPendingGrantsResult struct {
	Pending        []PendingGrant `json:"pending"`
	CurrentVersion int64          `json:"currentVersion"`
	RotationNeeded bool           `json:"rotationNeeded"`
}

// ListPendingGrants lists the members, directly, through a group or through
// everyone, who have published chat keys but lack a version of the channel key
// the caller holds. Members only; access errors are GetChannelKeys'.
func ListPendingGrants(params ListPendingGrantsParams) (ListPendingGrantsResult, error) {
	if params.Database == nil {
		return ListPendingGrantsResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if err := requireMember(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return ListPendingGrantsResult{}, err
	}
	state, err := loadKeyState(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return ListPendingGrantsResult{}, err
	}
	pending := []PendingGrant{}
	for _, p := range state.pending() {
		if state.holders[p.Version][params.Principal.UserID] {
			pending = append(pending, p)
		}
	}
	return ListPendingGrantsResult{Pending: pending, CurrentVersion: state.current, RotationNeeded: state.rotationNeeded()}, nil
}

// UploadGrantsParams stores grants the caller sealed and signed.
type UploadGrantsParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_key_granted. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	Grants    []GrantUpload
}

// UploadGrantsResult is the stored grant for each upload: the caller's, or
// the one that got there first.
type UploadGrantsResult struct {
	Grants []KeyGrant `json:"grants"`
}

// UploadGrants stores grants from a member who holds each version, to members
// with published chat keys. The first grant for a member and version wins and
// later ones are ignored. The caller's published signing key is recorded with
// each grant. Publishes chat_key_granted to the recipients.
func UploadGrants(params UploadGrantsParams) (UploadGrantsResult, error) {
	if len(params.Grants) == 0 || len(params.Grants) > MaxGrantsPerUpload {
		return UploadGrantsResult{}, ErrInvalidGrant
	}
	if params.Database == nil {
		return UploadGrantsResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if err := requireMember(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return UploadGrantsResult{}, err
	}
	signKey, err := callerSignKey(params.Ctx, queries, params.Principal)
	if err != nil {
		return UploadGrantsResult{}, err
	}
	state, err := loadKeyState(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return UploadGrantsResult{}, err
	}
	for _, g := range params.Grants {
		if !state.holders[g.Version][params.Principal.UserID] {
			return UploadGrantsResult{}, ErrNotHolder
		}
		if !validGrant(g.SealedKey, g.Signature) || state.boxKeys[g.UserID] == nil {
			return UploadGrantsResult{}, ErrInvalidGrant
		}
	}
	stored := make([]KeyGrant, 0, len(params.Grants))
	recipients := make([]int64, 0, len(params.Grants))
	for _, g := range params.Grants {
		row, err := insertGrant(params.Ctx, queries, params.ChannelID, g, params.Principal.UserID, signKey)
		if err != nil {
			return UploadGrantsResult{}, err
		}
		stored = append(stored, grantFromRow(row))
		recipients = append(recipients, g.UserID)
	}
	publishTo(params.EventBus, eventbus.EventChatKeyGranted, params.ChannelID, recipients)
	return UploadGrantsResult{Grants: stored}, nil
}

// CreateKeyVersionParams creates the next version of a channel's key, with the
// caller's own grant of it.
type CreateKeyVersionParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_key_needed, since the other members now lack the
	// new version. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	// Version must be one more than the newest, or 1 for a channel with none.
	Version   int64
	SealedKey []byte
	Signature []byte
}

// CreateKeyVersionResult is the new version, the caller's grant and the
// key_created event for the caller to sign.
type CreateKeyVersionResult struct {
	Version KeyVersion   `json:"version"`
	Grant   KeyGrant     `json:"grant"`
	Event   ChannelEvent `json:"event"`
}

// CreateKeyVersion lets any member start a channel's key, or rotate it,
// storing the caller's grant of the new key with it; the caller then fills
// the other members' grants through UploadGrants. A version that isn't the
// next one is ErrVersionConflict, so two clients racing to rotate leave one
// winner. Access errors are GetChannelKeys'.
func CreateKeyVersion(params CreateKeyVersionParams) (CreateKeyVersionResult, error) {
	if !validGrant(params.SealedKey, params.Signature) {
		return CreateKeyVersionResult{}, ErrInvalidGrant
	}
	if params.Database == nil {
		return CreateKeyVersionResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if err := requireMember(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return CreateKeyVersionResult{}, err
	}
	signKey, err := callerSignKey(params.Ctx, queries, params.Principal)
	if err != nil {
		return CreateKeyVersionResult{}, err
	}
	var result CreateKeyVersionResult
	err = inTx(params.Ctx, params.Database, func(q *db.Queries) error {
		versions, err := q.ListChatChannelKeys(params.Ctx, params.ChannelID)
		if err != nil {
			return err
		}
		if params.Version != int64(len(versions))+1 {
			return ErrVersionConflict
		}
		actor := sql.NullInt64{Int64: params.Principal.UserID, Valid: true}
		key, err := q.CreateChatChannelKey(params.Ctx, db.CreateChatChannelKeyParams{
			ChannelID: params.ChannelID, Version: params.Version, CreatedBy: actor,
		})
		if err != nil {
			return err
		}
		grant, err := insertGrant(params.Ctx, q, params.ChannelID, GrantUpload{
			Version: params.Version, UserID: params.Principal.UserID, SealedKey: params.SealedKey, Signature: params.Signature,
		}, params.Principal.UserID, signKey)
		if err != nil {
			return err
		}
		event, err := recordEvent(params.Ctx, q, params.ChannelID, EventKeyCreated, params.Principal.UserID, keyEventPayload{Version: params.Version})
		if err != nil {
			return err
		}
		result = CreateKeyVersionResult{Version: versionFromRow(key), Grant: grantFromRow(grant), Event: event}
		return nil
	})
	if sqlutil.IsUniqueConstraintErr(err) {
		return CreateKeyVersionResult{}, ErrVersionConflict
	}
	if err != nil {
		return CreateKeyVersionResult{}, err
	}
	if _, err := notifyChannel(params.Ctx, queries, params.EventBus, params.ChannelID); err != nil {
		return CreateKeyVersionResult{}, err
	}
	return result, nil
}

// ListEventsParams pages a channel's system events.
type ListEventsParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	ChannelID int64
	// After is the last event id already seen; 0 starts at the beginning.
	After int64
	// Limit is capped at MaxEventsPage; 0 means MaxEventsPage.
	Limit int64
}

// ListEventsResult is a page of events, oldest first.
type ListEventsResult struct {
	Events []ChannelEvent `json:"events"`
}

// ListEvents pages a channel's membership and key events for a member.
// Access errors are GetChannelKeys'.
func ListEvents(params ListEventsParams) (ListEventsResult, error) {
	if params.Database == nil {
		return ListEventsResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if err := requireMember(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return ListEventsResult{}, err
	}
	limit := params.Limit
	if limit <= 0 || limit > MaxEventsPage {
		limit = MaxEventsPage
	}
	rows, err := queries.ListChatChannelEvents(params.Ctx, db.ListChatChannelEventsParams{
		ChannelID: params.ChannelID, ID: params.After, Limit: limit,
	})
	if err != nil {
		return ListEventsResult{}, err
	}
	events := make([]ChannelEvent, 0, len(rows))
	for _, row := range rows {
		events = append(events, eventFromRow(row))
	}
	return ListEventsResult{Events: events}, nil
}

// SignEventParams attaches the actor's signature to an event.
type SignEventParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed, so members showing the event as
	// unverified refetch it (#2418). Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	EventID   int64
	Signature []byte
}

// SignEventResult is the event as now stored.
type SignEventResult struct {
	Event ChannelEvent
}

// SignEvent stores the caller's signature on an event the caller made, once,
// with the caller's published signing key beside it, and tells the members with
// chat_channel_changed. An event that isn't the caller's is ErrEventNotFound,
// and one already signed ErrEventSigned.
func SignEvent(params SignEventParams) (SignEventResult, error) {
	if len(params.Signature) != SignatureBytes {
		return SignEventResult{}, ErrInvalidGrant
	}
	if params.Database == nil {
		return SignEventResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if err := requireMember(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return SignEventResult{}, err
	}
	signKey, err := callerSignKey(params.Ctx, queries, params.Principal)
	if err != nil {
		return SignEventResult{}, err
	}
	signed, err := queries.SignChatChannelEvent(params.Ctx, db.SignChatChannelEventParams{
		Signature: params.Signature, SignerSignKey: signKey, ID: params.EventID, ChannelID: params.ChannelID,
		ActorID: sql.NullInt64{Int64: params.Principal.UserID, Valid: true},
	})
	if err != nil {
		return SignEventResult{}, err
	}
	row, err := queries.GetChatChannelEvent(params.Ctx, db.GetChatChannelEventParams{ID: params.EventID, ChannelID: params.ChannelID})
	switch {
	case errors.Is(err, sql.ErrNoRows) || (err == nil && row.ActorID.Int64 != params.Principal.UserID):
		return SignEventResult{}, ErrEventNotFound
	case err != nil:
		return SignEventResult{}, err
	case signed == 0:
		return SignEventResult{}, ErrEventSigned
	}
	members, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		log.Printf("chat: event %d signed but not announced: %v", params.EventID, err)
	}
	publish(params.EventBus, params.ChannelID, members)
	return SignEventResult{Event: eventFromRow(row)}, nil
}

// NotifyKeyNeededParams asks the Quark to look for grants that need filling.
type NotifyKeyNeededParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	EventBus *eventbus.Bus
}

// NotifyKeyNeededResult names the channels chat_key_needed went out for.
type NotifyKeyNeededResult struct {
	ChannelIDs []int64
}

// NotifyKeyNeeded publishes chat_key_needed, for every channel where a member
// with published chat keys lacks a version or the key needs rotating, to the
// members who hold a version and so can fill it. Clients also check when they
// open a channel, so a missed event only delays a grant.
func NotifyKeyNeeded(params NotifyKeyNeededParams) (NotifyKeyNeededResult, error) {
	if params.Database == nil {
		return NotifyKeyNeededResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	ids, err := queries.ListChatChannelIDs(params.Ctx)
	if err != nil {
		return NotifyKeyNeededResult{}, err
	}
	notified := []int64{}
	for _, id := range ids {
		sent, err := notifyChannel(params.Ctx, queries, params.EventBus, id)
		if err != nil {
			return NotifyKeyNeededResult{}, err
		}
		if sent {
			notified = append(notified, id)
		}
	}
	return NotifyKeyNeededResult{ChannelIDs: notified}, nil
}

// WatchKeyNeedsParams runs the Quark's key-need watcher.
type WatchKeyNeedsParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	EventBus *eventbus.Bus
}

// WatchKeyNeeds runs NotifyKeyNeeded whenever membership may have changed
// underneath a channel: access_changed (a group gained or lost an account),
// account_changed (an account was created, approved, turned off or deleted),
// and chat_channel_changed. It returns when Ctx is done; run it in its own
// goroutine for the life of the server.
func WatchKeyNeeds(params WatchKeyNeedsParams) {
	if params.EventBus == nil || params.Database == nil {
		return
	}
	events, unsubscribe := params.EventBus.Subscribe("chat-key-needs")
	defer unsubscribe()
	for {
		select {
		case <-params.Ctx.Done():
			return
		case evt, ok := <-events:
			if !ok {
				return
			}
			switch evt.Kind {
			case eventbus.EventAccessChanged, eventbus.EventAccountChanged, eventbus.EventChatChannelChanged:
				// ponytail: every membership event scans every channel again. Fine
				// for a household; debounce if bursts ever show up.
				if _, err := NotifyKeyNeeded(NotifyKeyNeededParams(params)); err != nil {
					log.Printf("[chatutil] key needs: %v", err)
				}
			}
		}
	}
}

// Message limits (#2418). A message's ciphertext is the 24-byte nonce, the
// encrypted body and the 16-byte tag, so anything shorter than MinCiphertext
// can't be one.
const (
	MaxCiphertextBytes = 16 << 10
	MinCiphertextBytes = 24 + 16
	// MaxMessageRequestBytes caps a post's body: the ciphertext in base64
	// plus room for the JSON around it.
	MaxMessageRequestBytes = 24 << 10
	// DefaultMessagesPage and MaxMessagesPage bound one ListMessages page.
	DefaultMessagesPage = 50
	MaxMessagesPage     = 200
)

var (
	// ErrMessageTooLarge reports ciphertext over MaxCiphertextBytes.
	ErrMessageTooLarge = errors.New("a message can be at most 16 KiB once encrypted")
	// ErrInvalidMessage reports ciphertext too short to be one, or a key
	// version the channel doesn't have.
	ErrInvalidMessage = errors.New("a message needs ciphertext under one of the channel's key versions")
	// ErrReadOnly reports a post from a member at read.
	ErrReadOnly = errors.New("you can read this channel but not post in it")
	// ErrMessageNotFound reports a message that doesn't exist or is in a
	// channel the caller isn't a member of.
	ErrMessageNotFound = errors.New("no message has that id")
	// ErrNotMessageAuthor reports deleting someone else's message without
	// owning the channel.
	ErrNotMessageAuthor = errors.New("only its author or an owner of the channel can delete a message")
)

// Message is one stored chat message. The Quark sees who sent it, when, and
// under which key version, never what it says. Byte fields travel as base64.
type Message struct {
	ID        int64 `json:"id"`
	ChannelID int64 `json:"channelId"`
	// AuthorID is absent once the author's account is deleted.
	AuthorID   int64 `json:"authorId,omitempty"`
	KeyVersion int64 `json:"keyVersion"`
	// Ciphertext is nonce || XChaCha20-Poly1305 output under the channel key
	// of KeyVersion, with the channel id and key version as additional data
	// (docs/chat-security.md). Absent once deleted.
	Ciphertext []byte     `json:"ciphertext,omitempty"`
	CreatedAt  time.Time  `json:"createdAt"`
	EditedAt   *time.Time `json:"editedAt,omitempty"`
	DeletedAt  *time.Time `json:"deletedAt,omitempty"`
}

// PostMessageParams posts ciphertext to a channel.
type PostMessageParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_message_created. Nil skips it.
	EventBus   *eventbus.Bus
	Principal  accessutil.Principal
	ChannelID  int64
	KeyVersion int64
	Ciphertext []byte
}

// PostMessageResult is the message as stored.
type PostMessageResult struct {
	Message Message
}

// PostMessage stores a message from a member at write or owner and sends it
// to the channel's members as chat_message_created. Ciphertext over the cap is
// ErrMessageTooLarge, a read member gets ErrReadOnly, and anyone else, admins
// included, ErrChannelNotFound.
func PostMessage(params PostMessageParams) (PostMessageResult, error) {
	if len(params.Ciphertext) > MaxCiphertextBytes {
		return PostMessageResult{}, ErrMessageTooLarge
	}
	if len(params.Ciphertext) < MinCiphertextBytes {
		return PostMessageResult{}, ErrInvalidMessage
	}
	if params.Database == nil {
		return PostMessageResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	level, err := memberLevel(params.Ctx, queries, params.Principal, params.ChannelID)
	if err != nil {
		return PostMessageResult{}, err
	}
	if level < accessutil.Write {
		return PostMessageResult{}, ErrReadOnly
	}
	versions, err := queries.ListChatChannelKeys(params.Ctx, params.ChannelID)
	if err != nil {
		return PostMessageResult{}, err
	}
	if !slices.ContainsFunc(versions, func(k db.ChatChannelKey) bool { return k.Version == params.KeyVersion }) {
		return PostMessageResult{}, ErrInvalidMessage
	}
	row, err := queries.CreateChatMessage(params.Ctx, db.CreateChatMessageParams{
		ChannelID:  params.ChannelID,
		AuthorID:   sql.NullInt64{Int64: params.Principal.UserID, Valid: true},
		KeyVersion: params.KeyVersion,
		Ciphertext: params.Ciphertext,
	})
	if err != nil {
		return PostMessageResult{}, err
	}
	message := messageFromRow(row)
	if err := publishMessage(params.Ctx, queries, params.EventBus, eventbus.EventChatMessageCreated, message); err != nil {
		log.Printf("chat: message %d stored but not announced: %v", row.ID, err)
	}
	return PostMessageResult{Message: message}, nil
}

// ListMessagesParams pages a channel's messages. Forward pages after After;
// otherwise the page ends before Before, or at the newest when Before is 0.
type ListMessagesParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	ChannelID int64
	Before    int64
	After     int64
	Forward   bool
	// Limit is capped at MaxMessagesPage; 0 means DefaultMessagesPage.
	Limit int64
}

// ListMessagesResult is a page of messages, oldest first, tombstones
// included.
type ListMessagesResult struct {
	Messages []Message `json:"messages"`
}

// ListMessages pages a channel's messages for a member. Access errors are
// GetChannelKeys'.
func ListMessages(params ListMessagesParams) (ListMessagesResult, error) {
	if params.Database == nil {
		return ListMessagesResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if _, err := memberLevel(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return ListMessagesResult{}, err
	}
	limit := params.Limit
	if limit <= 0 {
		limit = DefaultMessagesPage
	}
	limit = min(limit, MaxMessagesPage)
	var rows []db.ChatMessage
	var err error
	if params.Forward {
		rows, err = queries.ListChatMessagesAfter(params.Ctx, db.ListChatMessagesAfterParams{
			ChannelID: params.ChannelID, ID: params.After, Limit: limit,
		})
	} else {
		before := params.Before
		if before <= 0 {
			before = math.MaxInt64
		}
		rows, err = queries.ListChatMessagesBefore(params.Ctx, db.ListChatMessagesBeforeParams{
			ChannelID: params.ChannelID, ID: before, Limit: limit,
		})
		slices.Reverse(rows)
	}
	if err != nil {
		return ListMessagesResult{}, err
	}
	messages := make([]Message, 0, len(rows))
	for _, row := range rows {
		messages = append(messages, messageFromRow(row))
	}
	return ListMessagesResult{Messages: messages}, nil
}

// DeleteMessageParams deletes one message.
type DeleteMessageParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_message_deleted. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	MessageID int64
}

// DeleteMessageResult is the tombstone left behind.
type DeleteMessageResult struct {
	Message Message
}

// DeleteMessage wipes a message's ciphertext and marks it deleted, for its
// author or an owner of the channel, and tells the members. Anyone else in
// the channel gets ErrNotMessageAuthor; anyone outside it, admins included,
// ErrMessageNotFound.
func DeleteMessage(params DeleteMessageParams) (DeleteMessageResult, error) {
	if params.Database == nil {
		return DeleteMessageResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	row, err := queries.GetChatMessage(params.Ctx, params.MessageID)
	if errors.Is(err, sql.ErrNoRows) {
		return DeleteMessageResult{}, ErrMessageNotFound
	}
	if err != nil {
		return DeleteMessageResult{}, err
	}
	level, err := memberLevel(params.Ctx, queries, params.Principal, row.ChannelID)
	if errors.Is(err, ErrChannelNotFound) {
		return DeleteMessageResult{}, ErrMessageNotFound
	}
	if err != nil {
		return DeleteMessageResult{}, err
	}
	if row.AuthorID.Int64 != params.Principal.UserID && level < accessutil.Owner {
		return DeleteMessageResult{}, ErrNotMessageAuthor
	}
	row, err = queries.TombstoneChatMessage(params.Ctx, params.MessageID)
	if err != nil {
		return DeleteMessageResult{}, err
	}
	message := messageFromRow(row)
	if err := publishMessage(params.Ctx, queries, params.EventBus, eventbus.EventChatMessageDeleted, message); err != nil {
		log.Printf("chat: message %d deleted but not announced: %v", row.ID, err)
	}
	return DeleteMessageResult{Message: message}, nil
}
