// Package chatutil manages chat channels and who belongs to them (#2415).
//
// A Quark hosts one chat server, and the server has channels. A channel's
// members are rows naming one account or one group, each with a set of
// permissions (Perms), and the built-in everyone group reaches every active
// account. An account's effective set on a channel is the union of every row
// that reaches it; ResolvePerms works it out, and every check in this package
// goes through it. A channel is visible to anyone whose effective set is
// non-empty and a 404 to everyone else. general is seeded with the Member set
// for everyone, can't be deleted, and everyone can't leave it or drop below
// Viewer there.
//
// Changing membership needs PermManageMembers and is bounded without roles:
// you grant only what you hold, and you remove or downgrade only someone
// whose effective set is a strict subset of yours, unless you hold
// PermManageChannel. Only an admin removes or downgrades the creator's row,
// and only an admin may leave a channel that still has members without a
// holder of manage_channel (ErrLastOwner).
//
// Admins do not gain content: a channel they are not in stays out of their
// list unless they ask for every channel, and then it comes with an empty
// set, because its content is end-to-end encrypted and they could not read it
// anyway. They may still manage any channel, past every rule above: rename or
// delete it, and list or change its members. Any active account may create a
// channel and holds every permission on it.
//
// Every change publishes chat_channel_changed to the channel's members, before
// and after the change; accessutil.FilterEvent keeps it from everyone else.
//
// Channel keys (#2417) are made and shared by clients, never the Quark. A
// channel has key versions; a member holds a version through a grant, the key
// sealed to their X25519 key and signed by whoever granted it. The Quark works
// out who is missing a grant (holders of read_messages with published keys
// lacking a version; read_messages is the only permission that maps to the
// key) and whether the key needs rotating (someone without read_messages holds
// the current version), and tells the members who can act with
// chat_key_needed.
// Membership and key changes are also recorded as channel events, which the
// actor's client signs.
//
// Messages (#2418) are ciphertext under a channel key version; the Quark
// stores, pages and tombstones them and never opens one. Posting and deleting
// publish chat_message_created and chat_message_deleted to the channel's
// readers, the holders of read_messages, alone: delegated managers and admins
// who aren't readers hear neither, and like everyone else get
// ErrChannelNotFound for its messages.
//
// Reactions (#2426) are ciphertext too, one row per account, message and
// emoji; the Quark sees who reacted to what and when, not with what. Adding
// one needs add_reactions, removing your own the same, and removing someone
// else's manage_reactions. Both publish chat_reaction_changed to the readers
// alone, and a deleted message's reactions go with its tombstone.
package chatutil

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"slices"
	"strings"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"golang.org/x/crypto/blake2b"
)

// MaxNameLength and MaxTopicLength cap a channel's name and topic, in
// characters.
const (
	MaxNameLength  = 64
	MaxTopicLength = 512
)

// The sentinels' text is written for the app to show, so handlers send it out
// unwrapped. Grants reuse accessutil's ErrGrantTarget and ErrPrincipalNotFound.
var (
	// ErrChannelNotFound reports a channel that doesn't exist or on which the
	// caller's set is empty, so a non-member can't learn a channel's name.
	ErrChannelNotFound = errors.New("no channel has that id")
	// ErrForbidden reports a member without the permission a change needs.
	ErrForbidden = errors.New("you don't have the permission this needs in this channel")
	// ErrNotHeld reports granting a permission the caller doesn't hold.
	ErrNotHeld = errors.New("you can only grant permissions you hold")
	// ErrNotSubset reports removing or downgrading a member whose set isn't a
	// strict subset of the caller's, for a caller without manage_channel.
	ErrNotSubset = errors.New("you can only remove or demote members who hold less than you do")
	// ErrCreatorRow reports anyone but an admin removing or downgrading the
	// row of the account that created the channel.
	ErrCreatorRow = errors.New("only an admin can remove or demote the channel's creator")
	// ErrInvalidPerms reports a set of permissions that is unknown or
	// incoherent; the wrapping error names the problem.
	ErrInvalidPerms = errors.New("that set of permissions isn't valid")
	// ErrNoPerms reports giving a member the empty set, which is removing
	// them.
	ErrNoPerms = errors.New("a member needs at least one permission; remove them instead")
	// ErrInvalidName reports a name that is empty, too long, or holds a
	// control character once trimmed.
	ErrInvalidName = errors.New("a channel name has 1 to 64 characters and no line breaks or tabs")
	// ErrInvalidTopic reports a topic that is too long.
	ErrInvalidTopic = errors.New("a channel topic has at most 512 characters")
	// ErrNameTaken reports a name another channel already has, ignoring case.
	ErrNameTaken = errors.New("a channel with that name already exists")
	// ErrDefaultChannel reports deleting general.
	ErrDefaultChannel = errors.New("the general channel can't be deleted")
	// ErrDefaultEveryone reports removing everyone from general, or leaving it
	// without read_messages there.
	ErrDefaultEveryone = errors.New("everyone stays in the general channel and can always read it")
	// ErrMemberNotFound reports removing an account or group that has no row
	// on the channel.
	ErrMemberNotFound = errors.New("that account or group isn't a member of this channel")
	// ErrLastOwner reports a member who isn't an admin removing, demoting or
	// leaving as the last holder of manage_channel on a channel that still has
	// members, which would leave no one but admins able to manage it.
	ErrLastOwner = errors.New("this would leave no one who can manage the channel; give someone else manage_channel first")
	// ErrAdminOnly reports a member who isn't an admin asking for every
	// channel.
	ErrAdminOnly = errors.New("only an admin can list every channel")
)

// Perms is a set of chat channel permissions (#2415), stored in
// chat_channel_members.permissions as a bitmask. A bit's meaning is permanent:
// a retired permission keeps its bit forever. The API never shows the
// integer; a Perms travels as a JSON array of names.
//
// Seeing a channel is not a permission: a channel is visible to anyone whose
// effective set on it is non-empty. The message permissions need
// PermReadMessages (Validate); the management ones need nothing, so a
// manage-only set is a delegated manager, who runs a channel without being in
// the conversation or holding its key.
//
// Reserved for later phases, with no bit yet: attach_files, mention_everyone
// and pin_messages.
type Perms uint64

// The permissions, in bit order.
const (
	// PermReadMessages sees the channel and reads it: its name, topic,
	// members, history and live messages. The one permission that entitles a
	// key grant (#2417).
	PermReadMessages Perms = 1 << iota
	// PermSendMessages posts a message.
	PermSendMessages
	// PermAddReactions reacts to a message (#2426).
	PermAddReactions
	// PermDeleteMessages deletes other people's messages. Authors may delete
	// their own while they hold PermReadMessages.
	PermDeleteMessages
	// PermManageChannel renames the channel, changes its topic, deletes it.
	PermManageChannel
	// PermManageMembers adds and removes members and edits their sets.
	PermManageMembers
	// PermManageReactions removes other people's reactions (#2426). Anyone
	// with PermAddReactions may remove their own.
	PermManageReactions
)

// The presets the app offers (#2415). The Quark stores and serves only
// expanded sets and never tells a preset from a custom set; these name the
// sets it seeds and grants.
const (
	PresetViewer    = PermReadMessages
	PresetMember    = PresetViewer | PermSendMessages | PermAddReactions
	PresetModerator = PresetMember | PermDeleteMessages | PermManageReactions | PermManageMembers
	PresetOwner     = PresetModerator | PermManageChannel
	// PermsAll is every permission.
	PermsAll = PresetOwner
)

// permNames is each permission's name in bit order, as the API and swagger
// speak them.
var permNames = []string{
	"read_messages",
	"send_messages",
	"add_reactions",
	"delete_messages",
	"manage_channel",
	"manage_members",
	"manage_reactions",
}

// ParsePerms reads a list of permission names. An unknown name is
// ErrInvalidPerms; a repeated one is harmless. It checks no dependency; that
// is Validate.
func ParsePerms(names []string) (Perms, error) {
	var perms Perms
	for _, name := range names {
		i := slices.Index(permNames, name)
		if i < 0 {
			return 0, fmt.Errorf("%w: %q is not a permission", ErrInvalidPerms, name)
		}
		perms |= 1 << i
	}
	return perms, nil
}

// Has reports whether p holds every permission in q.
func (p Perms) Has(q Perms) bool { return p&q == q }

// Names lists p's permissions by name in bit order; never nil.
func (p Perms) Names() []string {
	names := []string{}
	for i, name := range permNames {
		if p&(1<<i) != 0 {
			names = append(names, name)
		}
	}
	return names
}

// String is p's names joined by commas.
func (p Perms) String() string { return strings.Join(p.Names(), ",") }

// Validate checks p is a set a member can hold: no bit outside PermsAll, and
// every message permission alongside PermReadMessages, since a client without
// the channel key can't read or encrypt a message. The error wraps
// ErrInvalidPerms and names the missing prerequisite. The empty set passes;
// whether it is allowed is the caller's to say.
func (p Perms) Validate() error {
	if p&^PermsAll != 0 {
		return fmt.Errorf("%w: unknown permission bits", ErrInvalidPerms)
	}
	if p.Has(PermReadMessages) {
		return nil
	}
	for _, needsRead := range []Perms{PermSendMessages, PermAddReactions, PermDeleteMessages, PermManageReactions} {
		if p.Has(needsRead) {
			return fmt.Errorf("%w: %s needs read_messages", ErrInvalidPerms, needsRead)
		}
	}
	return nil
}

// MarshalJSON writes p as an array of names.
func (p Perms) MarshalJSON() ([]byte, error) { return json.Marshal(p.Names()) }

// UnmarshalJSON reads an array of names with ParsePerms.
func (p *Perms) UnmarshalJSON(data []byte) error {
	var names []string
	if err := json.Unmarshal(data, &names); err != nil {
		return err
	}
	parsed, err := ParsePerms(names)
	if err != nil {
		return err
	}
	*p = parsed
	return nil
}

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
	// Permissions is the caller's effective set: the union of every row that
	// reaches them. Empty for an admin managing a channel they are not in.
	Permissions Perms `json:"permissions" swaggertype:"array,string" enums:"read_messages,send_messages,add_reactions,delete_messages,manage_channel,manage_members,manage_reactions"`
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
	// Permissions is this row's set, not anyone's effective one.
	Permissions Perms `json:"permissions" swaggertype:"array,string" enums:"read_messages,send_messages,add_reactions,delete_messages,manage_channel,manage_members,manage_reactions"`
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

// ResolvedUser is an active account a channel's rows reach, with its
// effective set.
type ResolvedUser struct {
	UserID   int64
	Username string
	Perms    Perms
}

// ResolvePermsParams names an account and a channel.
type ResolvePermsParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	ChannelID int64
	Principal accessutil.Principal
}

// ResolvePermsResult is the account's effective set on the channel.
type ResolvePermsResult struct {
	Perms Perms
}

// ResolvePerms is an account's effective set on a channel: the union of its
// own row, the row of each group it is in, and everyone's row. Empty for a
// non-member, a missing channel, and a principal with no account. Admins get
// no more than their rows give them.
func ResolvePerms(params ResolvePermsParams) (ResolvePermsResult, error) {
	if params.Database == nil {
		return ResolvePermsResult{}, accessutil.ErrNoDatabase
	}
	perms, err := resolvePerms(params.Ctx, params.Database.Queries, params.ChannelID, params.Principal.UserID)
	return ResolvePermsResult{Perms: perms}, err
}

// ListChannelsParams asks for the caller's channels.
type ListChannelsParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	// All adds, for an admin, the channels they are not a member of
	// (ErrAdminOnly for anyone else).
	All bool
}

// ListChannelsResult is the caller's channels, general first, then by name.
type ListChannelsResult struct {
	Channels []Channel `json:"channels"`
}

// ListChannels lists the channels the caller has a non-empty set on, directly,
// through a group, or through everyone, each with that set. Admins get only
// their own channels too, unless they ask for All: then the channels they are
// not in follow, in the same order, with an empty set, so they can manage them
// without reading them.
func ListChannels(params ListChannelsParams) (ListChannelsResult, error) {
	if params.Database == nil {
		return ListChannelsResult{}, accessutil.ErrNoDatabase
	}
	if params.All && !params.Principal.IsAdmin {
		return ListChannelsResult{}, ErrAdminOnly
	}
	rows, err := params.Database.Queries.ListChatChannelsForUser(params.Ctx,
		sql.NullInt64{Int64: params.Principal.UserID, Valid: true})
	if err != nil {
		return ListChannelsResult{}, err
	}
	// One row per membership row: union each channel's, keeping the query's
	// order.
	channels := []Channel{}
	for _, row := range rows {
		if n := len(channels); n > 0 && channels[n-1].ID == row.ID {
			channels[n-1].Permissions |= Perms(row.Permissions)
			continue
		}
		channels = append(channels, Channel{
			ID:          row.ID,
			ServerID:    row.ServerID,
			Kind:        row.Kind,
			Name:        row.Name,
			Topic:       row.Topic,
			IsDefault:   row.IsDefault != 0,
			IsPrivate:   row.IsPrivate != 0,
			Permissions: Perms(row.Permissions),
			CreatedBy:   row.CreatedBy.Int64,
			CreatedAt:   row.CreatedAt,
		})
	}
	if !params.All {
		return ListChannelsResult{Channels: channels}, nil
	}
	all, err := params.Database.Queries.ListAllChatChannels(params.Ctx)
	if err != nil {
		return ListChannelsResult{}, err
	}
	for _, row := range all {
		if slices.ContainsFunc(channels, func(c Channel) bool { return c.ID == row.ID }) {
			continue
		}
		channels = append(channels, Channel{
			ID:        row.ID,
			ServerID:  row.ServerID,
			Kind:      row.Kind,
			Name:      row.Name,
			Topic:     row.Topic,
			IsDefault: row.IsDefault != 0,
			IsPrivate: row.IsPrivate != 0,
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

// CreateChannel creates a private channel on the Quark's server and gives the
// caller every permission on it. The name is trimmed and must be unique
// ignoring case (ErrNameTaken).
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
			ChannelID: row.ID, UserID: creator, Permissions: int64(PermsAll),
		})
	})
	if sqlutil.IsUniqueConstraintErr(err) {
		return CreateChannelResult{}, ErrNameTaken
	}
	if err != nil {
		return CreateChannelResult{}, err
	}
	publish(params.EventBus, row.ID, []int64{params.Principal.UserID})
	return CreateChannelResult{Channel: channelFromRow(row, PermsAll, true)}, nil
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

// UpdateChannel renames a channel or changes its topic, for a holder of
// manage_channel or an admin. Anyone with an empty set who isn't an admin gets
// ErrChannelNotFound, and a member without manage_channel ErrForbidden.
func UpdateChannel(params UpdateChannelParams) (UpdateChannelResult, error) {
	if params.Database == nil {
		return UpdateChannelResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	current, perms, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, PermManageChannel)
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
	return UpdateChannelResult{Channel: channelFromRow(row, perms, private)}, nil
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

// DeleteChannel deletes a channel and its members, for a holder of
// manage_channel or an admin. general can't be deleted (ErrDefaultChannel).
// Access errors are UpdateChannel's.
func DeleteChannel(params DeleteChannelParams) (DeleteChannelResult, error) {
	if params.Database == nil {
		return DeleteChannelResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	current, _, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, PermManageChannel)
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
// it, for anyone with a non-empty set on the channel, delegated managers
// included, or an admin. Anyone else gets ErrChannelNotFound.
func ListMembers(params ListMembersParams) (ListMembersResult, error) {
	if params.Database == nil {
		return ListMembersResult{}, accessutil.ErrNoDatabase
	}
	if _, _, err := authorize(params.Ctx, params.Database.Queries, params.Principal, params.ChannelID, 0); err != nil {
		return ListMembersResult{}, err
	}
	return listMembers(params.Ctx, params.Database.Queries, params.ChannelID, params.DataDir)
}

// SetMemberParams gives one account or group a set on a channel. Exactly one
// of UserID and GroupID is set.
type SetMemberParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed. Nil skips it.
	EventBus    *eventbus.Bus
	Principal   accessutil.Principal
	ChannelID   int64
	UserID      int64
	GroupID     int64
	Permissions Perms
	// DataDir is where profile pictures are, for the returned members.
	DataDir string
}

// SetMember adds an account or group to a channel, or replaces its row's set,
// and returns the channel's members as they now stand. The set must be
// coherent and non-empty (ErrInvalidPerms, ErrNoPerms). It answers to a holder
// of manage_members, within the escalation bound, or an admin: granting a
// permission the caller lacks is ErrNotHeld; taking one away from a row is a
// downgrade, allowed only when the target's set is a strict subset of the
// caller's or the caller holds manage_channel (ErrNotSubset), and never on
// the creator's row (ErrCreatorRow). everyone keeps read_messages on general
// (ErrDefaultEveryone). Other access errors are UpdateChannel's; the account
// must be active and the group must exist (accessutil.ErrPrincipalNotFound).
func SetMember(params SetMemberParams) (ListMembersResult, error) {
	if (params.UserID == 0) == (params.GroupID == 0) {
		return ListMembersResult{}, accessutil.ErrGrantTarget
	}
	if err := params.Permissions.Validate(); err != nil {
		return ListMembersResult{}, err
	}
	if params.Permissions == 0 {
		return ListMembersResult{}, ErrNoPerms
	}
	if params.Database == nil {
		return ListMembersResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	channel, callerPerms, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, PermManageMembers)
	if err != nil {
		return ListMembersResult{}, err
	}
	if err := ensurePrincipal(params.Ctx, queries, params.UserID, params.GroupID); err != nil {
		return ListMembersResult{}, err
	}
	if channel.IsDefault != 0 && params.GroupID != 0 && !params.Permissions.Has(PresetViewer) {
		everyone, err := isEveryone(params.Ctx, queries, params.GroupID)
		if err != nil {
			return ListMembersResult{}, err
		}
		if everyone {
			return ListMembersResult{}, ErrDefaultEveryone
		}
	}
	if !params.Principal.IsAdmin {
		if params.Permissions&^callerPerms != 0 {
			return ListMembersResult{}, ErrNotHeld
		}
		row, err := memberRow(params.Ctx, queries, params.ChannelID, params.UserID, params.GroupID)
		if err != nil {
			return ListMembersResult{}, err
		}
		if row&^params.Permissions != 0 {
			if err := mayDemote(params.Ctx, queries, params.Principal, channel, callerPerms, params.UserID, row); err != nil {
				return ListMembersResult{}, err
			}
		}
	}
	before, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	err = keepingAnOwner(params.Ctx, params.Database, params.Principal, params.ChannelID, func(q *db.Queries) error {
		if params.UserID != 0 {
			return q.SetChatChannelUserMember(params.Ctx, db.SetChatChannelUserMemberParams{
				ChannelID:   params.ChannelID,
				UserID:      sql.NullInt64{Int64: params.UserID, Valid: true},
				Permissions: int64(params.Permissions),
			})
		}
		return q.SetChatChannelGroupMember(params.Ctx, db.SetChatChannelGroupMemberParams{
			ChannelID:   params.ChannelID,
			GroupID:     sql.NullInt64{Int64: params.GroupID, Valid: true},
			Permissions: int64(params.Permissions),
		})
	})
	if err != nil {
		return ListMembersResult{}, err
	}
	payload, err := memberPayload(params.Ctx, queries, params.UserID, params.GroupID, params.Permissions)
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
// as they now stand. Any member may remove their own account's row, which is
// leaving. Removing anyone else needs manage_members and the same bound as a
// downgrade in SetMember (ErrNotSubset, ErrCreatorRow); admins are exempt.
// everyone can't be removed from general (ErrDefaultEveryone), and a principal
// with no row is ErrMemberNotFound. Other access errors are UpdateChannel's.
func RemoveMember(params RemoveMemberParams) (ListMembersResult, error) {
	if (params.UserID == 0) == (params.GroupID == 0) {
		return ListMembersResult{}, accessutil.ErrGrantTarget
	}
	if params.Database == nil {
		return ListMembersResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	leaving := params.UserID != 0 && params.UserID == params.Principal.UserID
	required := PermManageMembers
	if leaving {
		required = 0
	}
	channel, callerPerms, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, required)
	if err != nil {
		return ListMembersResult{}, err
	}
	if channel.IsDefault != 0 && params.GroupID != 0 {
		everyone, err := isEveryone(params.Ctx, queries, params.GroupID)
		if err != nil {
			return ListMembersResult{}, err
		}
		if everyone {
			return ListMembersResult{}, ErrDefaultEveryone
		}
	}
	row, err := memberRow(params.Ctx, queries, params.ChannelID, params.UserID, params.GroupID)
	if err != nil {
		return ListMembersResult{}, err
	}
	if row == 0 {
		return ListMembersResult{}, ErrMemberNotFound
	}
	if !leaving && !params.Principal.IsAdmin {
		if err := mayDemote(params.Ctx, queries, params.Principal, channel, callerPerms, params.UserID, row); err != nil {
			return ListMembersResult{}, err
		}
	}
	before, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	payload, err := memberPayload(params.Ctx, queries, params.UserID, params.GroupID, 0)
	if errors.Is(err, sql.ErrNoRows) {
		return ListMembersResult{}, ErrMemberNotFound
	}
	if err != nil {
		return ListMembersResult{}, err
	}
	err = keepingAnOwner(params.Ctx, params.Database, params.Principal, params.ChannelID, func(q *db.Queries) error {
		var deleted int64
		var err error
		if params.UserID != 0 {
			deleted, err = q.DeleteChatChannelUserMember(params.Ctx, db.DeleteChatChannelUserMemberParams{
				ChannelID: params.ChannelID,
				UserID:    sql.NullInt64{Int64: params.UserID, Valid: true},
			})
		} else {
			deleted, err = q.DeleteChatChannelGroupMember(params.Ctx, db.DeleteChatChannelGroupMemberParams{
				ChannelID: params.ChannelID,
				GroupID:   sql.NullInt64{Int64: params.GroupID, Valid: true},
			})
		}
		if err == nil && deleted == 0 {
			err = ErrMemberNotFound
		}
		return err
	})
	if err != nil {
		return ListMembersResult{}, err
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
// reach, directly, through a group, or through everyone, each with its
// effective set, by username. It checks no caller: it is for the Quark's own
// use, such as working out who needs a channel key (#2417).
func ResolveMemberUsers(params ResolveMemberUsersParams) (ResolveMemberUsersResult, error) {
	if params.Database == nil {
		return ResolveMemberUsersResult{}, accessutil.ErrNoDatabase
	}
	users, err := memberUsers(params.Ctx, params.Database.Queries, params.ChannelID)
	return ResolveMemberUsersResult{Users: users}, err
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
	// ErrRotationNotNeeded reports creating a key version after the first
	// while nobody outside the channel holds the current one.
	ErrRotationNotNeeded = errors.New("the channel key doesn't need rotating")
	// ErrInvalidGrant reports a grant of the wrong size, or for an account
	// that isn't a member with published chat keys.
	ErrInvalidGrant = errors.New("that key grant is malformed or names someone who can't receive it")
	// ErrGrantSignature reports a grant whose signature doesn't verify
	// against the caller's published signing key.
	ErrGrantSignature = errors.New("that key grant's signature doesn't match your chat keys")
	// ErrGrantNotFound reports rejecting a grant the caller doesn't have.
	ErrGrantNotFound = errors.New("you have no grant of that key version")
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

// GrantMessage is the bytes a grant's signature covers (#2417):
//
//	"quark-chat-grant-v1" 0x00 || be64(channelId) || be64(version) ||
//	be64(recipientUserId) || BLAKE2b-256(sealedKey)
//
// It must match the app's ChatCrypto.grantMessage byte for byte.
func GrantMessage(channelID, version, userID int64, sealedKey []byte) []byte {
	msg := append([]byte("quark-chat-grant-v1"), 0)
	for _, n := range []int64{channelID, version, userID} {
		msg = binary.BigEndian.AppendUint64(msg, uint64(n))
	}
	sum := blake2b.Sum256(sealedKey)
	return append(msg, sum[:]...)
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
	// change {"userId"|"groupId", "name", "permissions"}, for a key {"version"}.
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
	// RotationNeeded is set when someone holding the current version no longer
	// holds read_messages; the next member client online creates the next one.
	RotationNeeded bool `json:"rotationNeeded"`
}

// GetChannelKeys returns a channel's key versions and the caller's grants,
// for holders of read_messages only: anyone else, delegated managers and
// admins included, gets ErrChannelNotFound.
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
// the caller holds. Needs read_messages; access errors are GetChannelKeys'.
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
		if !grantSigned(signKey, params.ChannelID, g) {
			return UploadGrantsResult{}, ErrGrantSignature
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

// RejectGrantParams drops the caller's own grant of one key version.
type RejectGrantParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_key_needed, so a holder refills the grant. Nil
	// skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	Version   int64
}

// RejectGrantResult is the version the caller is pending for again.
type RejectGrantResult struct {
	Version int64 `json:"version"`
}

// RejectGrant lets a recipient drop a grant addressed to them that they can't
// open or verify (#2486). Grants are first-write-wins, so without this a
// member could squat a victim's grant with a signed but useless sealed key.
// The caller is pending again, and the holders hear chat_key_needed. A grant
// the caller doesn't have is ErrGrantNotFound; access errors are
// GetChannelKeys'.
func RejectGrant(params RejectGrantParams) (RejectGrantResult, error) {
	if params.Database == nil {
		return RejectGrantResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if err := requireMember(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		return RejectGrantResult{}, err
	}
	n, err := queries.DeleteChatKeyGrant(params.Ctx, db.DeleteChatKeyGrantParams{
		ChannelID: params.ChannelID, Version: params.Version,
		UserID: sql.NullInt64{Int64: params.Principal.UserID, Valid: true},
	})
	if err != nil {
		return RejectGrantResult{}, err
	}
	if n == 0 {
		return RejectGrantResult{}, ErrGrantNotFound
	}
	if _, err := notifyChannel(params.Ctx, queries, params.EventBus, params.ChannelID); err != nil {
		return RejectGrantResult{}, err
	}
	return RejectGrantResult{Version: params.Version}, nil
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

// CreateKeyVersion lets any member start a channel's key, or rotate it once
// rotation is needed (ErrRotationNotNeeded otherwise), storing the caller's
// grant of the new key with it; the caller then fills the other members'
// grants through UploadGrants. A version that isn't the
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
	own := GrantUpload{Version: params.Version, UserID: params.Principal.UserID, SealedKey: params.SealedKey, Signature: params.Signature}
	if !grantSigned(signKey, params.ChannelID, own) {
		return CreateKeyVersionResult{}, ErrGrantSignature
	}
	var result CreateKeyVersionResult
	err = inTx(params.Ctx, params.Database, func(q *db.Queries) error {
		state, err := loadKeyState(params.Ctx, q, params.ChannelID)
		if err != nil {
			return err
		}
		if params.Version != int64(len(state.versions))+1 {
			return ErrVersionConflict
		}
		// Only a removal rotates the key (#2485): without one, a member could
		// mint versions at will and bury the channel's history under them.
		if state.current > 0 && !state.rotationNeeded() {
			return ErrRotationNotNeeded
		}
		actor := sql.NullInt64{Int64: params.Principal.UserID, Valid: true}
		key, err := q.CreateChatChannelKey(params.Ctx, db.CreateChatChannelKeyParams{
			ChannelID: params.ChannelID, Version: params.Version, CreatedBy: actor,
		})
		if err != nil {
			return err
		}
		grant, err := insertGrant(params.Ctx, q, params.ChannelID, own, params.Principal.UserID, signKey)
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
// and one already signed ErrEventSigned. The actor needn't be a member any
// more: leaving, or an admin managing a channel they are not in, makes an event
// its actor can only sign from outside (#2422). Anyone else learns nothing,
// since only the actor's own events answer anything but ErrEventNotFound.
func SignEvent(params SignEventParams) (SignEventResult, error) {
	if len(params.Signature) != SignatureBytes {
		return SignEventResult{}, ErrInvalidGrant
	}
	if params.Database == nil {
		return SignEventResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if params.Principal.UserID == 0 {
		return SignEventResult{}, ErrEventNotFound
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
			case eventbus.EventAccessChanged, eventbus.EventAccountChanged, eventbus.EventChatChannelChanged,
				eventbus.EventResync:
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
	// ErrReadOnly reports a post from a member without send_messages.
	ErrReadOnly = errors.New("you can read this channel but not send messages in it")
	// ErrMessageNotFound reports a message that doesn't exist or is in a
	// channel the caller doesn't read.
	ErrMessageNotFound = errors.New("no message has that id")
	// ErrNotMessageAuthor reports deleting someone else's message without
	// delete_messages.
	ErrNotMessageAuthor = errors.New("only its author or a member with delete_messages can delete a message")
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
	// Reactions are the message's reactions, oldest first, in a
	// ListMessages page. A deleted message has none: they go with its
	// ciphertext.
	Reactions []Reaction `json:"reactions,omitempty"`
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

// PostMessage stores a message from a member holding send_messages and sends
// it to the channel's readers as chat_message_created. Ciphertext over the cap
// is ErrMessageTooLarge, a reader without send_messages gets ErrReadOnly, and
// anyone without read_messages, delegated managers and admins included,
// ErrChannelNotFound.
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
	perms, err := memberPerms(params.Ctx, queries, params.Principal, params.ChannelID)
	if err != nil {
		return PostMessageResult{}, err
	}
	if !perms.Has(PermSendMessages) {
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
// included, each with its reactions.
type ListMessagesResult struct {
	Messages []Message `json:"messages"`
}

// ListMessages pages a channel's messages for a holder of read_messages.
// Access errors are GetChannelKeys'.
func ListMessages(params ListMessagesParams) (ListMessagesResult, error) {
	if params.Database == nil {
		return ListMessagesResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	if _, err := memberPerms(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
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
	if err := attachReactions(params.Ctx, queries, params.ChannelID, messages); err != nil {
		return ListMessagesResult{}, err
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
// author or a holder of delete_messages, and tells the readers. Either must
// hold read_messages now: anyone without it, an author who was removed or
// demoted to a manage-only set and admins included, gets ErrMessageNotFound,
// and a reader who is neither ErrNotMessageAuthor.
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
	perms, err := memberPerms(params.Ctx, queries, params.Principal, row.ChannelID)
	if errors.Is(err, ErrChannelNotFound) {
		return DeleteMessageResult{}, ErrMessageNotFound
	}
	if err != nil {
		return DeleteMessageResult{}, err
	}
	if row.AuthorID.Int64 != params.Principal.UserID && !perms.Has(PermDeleteMessages) {
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

// Reaction limits (#2426). A reaction's ciphertext is a padded emoji under
// the channel key, so it is small; MaxReactionsPerUser bounds how many rows
// one account can pile onto a message, since the Quark can't tell two of
// them apart.
const (
	MaxReactionCiphertextBytes = 256
	// MaxReactionRequestBytes caps an add's body: the ciphertext in base64
	// plus room for the JSON around it.
	MaxReactionRequestBytes = 1 << 10
	MaxReactionsPerUser     = 20
)

var (
	// ErrInvalidReaction reports ciphertext too short or too long to be a
	// reaction, or a key version the channel doesn't have.
	ErrInvalidReaction = errors.New("a reaction needs ciphertext under one of the channel's key versions")
	// ErrNoReactions reports a reader without add_reactions reacting, or
	// removing a reaction of their own.
	ErrNoReactions = errors.New("you can read this channel but not react in it")
	// ErrTooManyReactions reports an account at MaxReactionsPerUser on one
	// message.
	ErrTooManyReactions = errors.New("you have reacted to this message as many times as you can")
	// ErrMessageDeleted reports reacting to a deleted message.
	ErrMessageDeleted = errors.New("that message was deleted")
	// ErrReactionNotFound reports a reaction that doesn't exist or is in a
	// channel the caller doesn't read.
	ErrReactionNotFound = errors.New("no reaction has that id")
	// ErrNotReactionAuthor reports removing someone else's reaction without
	// manage_reactions.
	ErrNotReactionAuthor = errors.New("only its author or a member with manage_reactions can remove a reaction")
)

// Reaction is one stored reaction. The Quark sees who reacted to which
// message and when, never with what. Byte fields travel as base64.
type Reaction struct {
	ID        int64 `json:"id"`
	MessageID int64 `json:"messageId"`
	UserID    int64 `json:"userId"`
	// KeyVersion is the channel key the reaction was encrypted under, which
	// needn't be its message's.
	KeyVersion int64 `json:"keyVersion"`
	// Ciphertext is nonce || XChaCha20-Poly1305 output under the channel key
	// of KeyVersion, with the channel, key version, message and reacting
	// account as additional data (docs/chat-security.md).
	Ciphertext []byte    `json:"ciphertext"`
	CreatedAt  time.Time `json:"createdAt"`
}

// AddReactionParams reacts to a message with ciphertext.
type AddReactionParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_reaction_changed. Nil skips it.
	EventBus   *eventbus.Bus
	Principal  accessutil.Principal
	MessageID  int64
	KeyVersion int64
	Ciphertext []byte
}

// AddReactionResult is the reaction as stored.
type AddReactionResult struct {
	Reaction Reaction
}

// AddReaction stores a reaction from a reader holding add_reactions and sends
// it to the channel's readers as chat_reaction_changed. Anyone without
// read_messages, delegated managers and admins included, gets
// ErrMessageNotFound; a reader without add_reactions ErrNoReactions; a
// deleted message ErrMessageDeleted; and an account already at
// MaxReactionsPerUser on the message ErrTooManyReactions.
func AddReaction(params AddReactionParams) (AddReactionResult, error) {
	if len(params.Ciphertext) < MinCiphertextBytes || len(params.Ciphertext) > MaxReactionCiphertextBytes {
		return AddReactionResult{}, ErrInvalidReaction
	}
	if params.Database == nil {
		return AddReactionResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	message, perms, err := readableMessage(params.Ctx, queries, params.Principal, params.MessageID)
	if err != nil {
		return AddReactionResult{}, err
	}
	if !perms.Has(PermAddReactions) {
		return AddReactionResult{}, ErrNoReactions
	}
	if message.DeletedAt.Valid {
		return AddReactionResult{}, ErrMessageDeleted
	}
	versions, err := queries.ListChatChannelKeys(params.Ctx, message.ChannelID)
	if err != nil {
		return AddReactionResult{}, err
	}
	if !slices.ContainsFunc(versions, func(k db.ChatChannelKey) bool { return k.Version == params.KeyVersion }) {
		return AddReactionResult{}, ErrInvalidReaction
	}
	held, err := queries.CountUserChatReactions(params.Ctx, db.CountUserChatReactionsParams{
		MessageID: params.MessageID, UserID: params.Principal.UserID,
	})
	if err != nil {
		return AddReactionResult{}, err
	}
	if held >= MaxReactionsPerUser {
		return AddReactionResult{}, ErrTooManyReactions
	}
	row, err := queries.CreateChatReaction(params.Ctx, db.CreateChatReactionParams{
		MessageID:  params.MessageID,
		UserID:     params.Principal.UserID,
		KeyVersion: params.KeyVersion,
		Ciphertext: params.Ciphertext,
	})
	if errors.Is(err, sql.ErrNoRows) {
		// Deleted between the read above and the insert.
		return AddReactionResult{}, ErrMessageDeleted
	}
	if err != nil {
		return AddReactionResult{}, err
	}
	reaction := reactionFromRow(row)
	if err := publishReaction(params.Ctx, queries, params.EventBus, message.ChannelID, reaction.MessageID, reaction.ID, &reaction); err != nil {
		log.Printf("chat: reaction %d stored but not announced: %v", row.ID, err)
	}
	return AddReactionResult{Reaction: reaction}, nil
}

// RemoveReactionParams removes one reaction.
type RemoveReactionParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_reaction_changed. Nil skips it.
	EventBus   *eventbus.Bus
	Principal  accessutil.Principal
	ReactionID int64
}

// RemoveReactionResult is the reaction that was removed.
type RemoveReactionResult struct {
	Reaction Reaction
}

// RemoveReaction deletes a reaction and tells the channel's readers with a
// chat_reaction_changed that carries no reaction. Removing your own needs
// add_reactions (ErrNoReactions) and someone else's manage_reactions
// (ErrNotReactionAuthor); either way the caller must hold read_messages now,
// or gets ErrReactionNotFound, delegated managers and admins included.
func RemoveReaction(params RemoveReactionParams) (RemoveReactionResult, error) {
	if params.Database == nil {
		return RemoveReactionResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	row, err := queries.GetChatReaction(params.Ctx, params.ReactionID)
	if errors.Is(err, sql.ErrNoRows) {
		return RemoveReactionResult{}, ErrReactionNotFound
	}
	if err != nil {
		return RemoveReactionResult{}, err
	}
	message, perms, err := readableMessage(params.Ctx, queries, params.Principal, row.MessageID)
	if errors.Is(err, ErrMessageNotFound) {
		return RemoveReactionResult{}, ErrReactionNotFound
	}
	if err != nil {
		return RemoveReactionResult{}, err
	}
	switch {
	case row.UserID == params.Principal.UserID && !perms.Has(PermAddReactions):
		return RemoveReactionResult{}, ErrNoReactions
	case row.UserID != params.Principal.UserID && !perms.Has(PermManageReactions):
		return RemoveReactionResult{}, ErrNotReactionAuthor
	}
	if err := queries.DeleteChatReaction(params.Ctx, row.ID); err != nil {
		return RemoveReactionResult{}, err
	}
	if err := publishReaction(params.Ctx, queries, params.EventBus, message.ChannelID, row.MessageID, row.ID, nil); err != nil {
		log.Printf("chat: reaction %d removed but not announced: %v", row.ID, err)
	}
	return RemoveReactionResult{Reaction: reactionFromRow(row)}, nil
}
