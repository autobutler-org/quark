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
package chatutil

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
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
	return afterMembershipChange(params.Ctx, queries, params.EventBus, params.ChannelID, before, params.DataDir)
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
	return afterMembershipChange(params.Ctx, queries, params.EventBus, params.ChannelID, before, params.DataDir)
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
// had.
func PutKeys(params PutKeysParams) (PutKeysResult, error) {
	if err := ValidateKeys(params.Keys); err != nil {
		return PutKeysResult{}, err
	}
	k := params.Keys
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
