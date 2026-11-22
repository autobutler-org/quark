package chatutil

import (
	"context"
	"crypto/rand"
	"database/sql"
	"errors"
	"fmt"
	"math/big"
	"slices"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

// Anonymous channels (#2949). A channel created anonymous shows each account
// in it to the other members only by a per-channel pseudonym: a random
// negative id and an alias. Wherever a member's id or username would reach a
// member, the Quark serves the pseudonym instead: in the member list, on
// messages, reactions, poll answers, key versions, grants, pending grants,
// channel events and typing. Admins and holders of manage_members also see
// who is behind each pseudonym in the member list, and may change anyone's
// alias; every member may change their own.
// docs/chat-security.md says what this does not hide.

// MaxAliasLength caps an alias, in characters.
const MaxAliasLength = 32

var (
	// ErrInvalidAlias reports an alias that is empty, too long, or holds a
	// control character once trimmed.
	ErrInvalidAlias = errors.New("an alias has 1 to 32 characters and no line breaks or tabs")
	// ErrAliasTaken reports an alias someone else in the channel goes by, or
	// an account's username, in any case.
	ErrAliasTaken = errors.New("someone already goes by that name")
	// errNoFreePseudonym reports eight draws of a default alias in a row
	// that were all usernames.
	errNoFreePseudonym = errors.New("no default alias left that isn't a username")
	// ErrNotAnonymous reports setting an alias in a channel that isn't
	// anonymous.
	ErrNotAnonymous = errors.New("only an anonymous channel has aliases")
)

// SetAliasParams renames one account's pseudonym in an anonymous channel.
type SetAliasParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed, so open clients read the members
	// again. Nil skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	ChannelID int64
	// UserID names the account by its id or its pseudonym.
	UserID int64
	Alias  string
	// DataDir is where profile pictures are, for the returned members.
	DataDir string
}

// SetAlias renames an account's pseudonym in an anonymous channel and returns
// the channel's members as they now stand, as ListMembers shows them to the
// caller. Any member may rename themselves, by account id or pseudonym;
// renaming anyone else needs manage_members or an admin, and a member without
// either who names anyone else gets ErrForbidden, whether or not the id names
// someone. The alias is trimmed and must be valid (ErrInvalidAlias), unique in
// the channel and no account's username, in any case (ErrAliasTaken). A
// channel that isn't anonymous is ErrNotAnonymous, and an account the
// channel's rows don't reach that has no pseudonym there ErrMemberNotFound.
// Other access errors are authorize's.
func SetAlias(params SetAliasParams) (ListMembersResult, error) {
	alias := strings.TrimSpace(params.Alias)
	if alias == "" || utf8.RuneCountInString(alias) > MaxAliasLength || strings.ContainsFunc(alias, unicode.IsControl) {
		return ListMembersResult{}, ErrInvalidAlias
	}
	if params.Database == nil {
		return ListMembersResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	channel, perms, err := authorize(params.Ctx, queries, params.Principal, params.ChannelID, 0)
	if err != nil {
		return ListMembersResult{}, err
	}
	managing := privileged(params.Principal, perms)
	p, err := pseudonymsOf(params.Ctx, queries, channel)
	if err != nil {
		return ListMembersResult{}, err
	}
	if p == nil {
		return ListMembersResult{}, ErrNotAnonymous
	}
	audience, err := memberIDs(params.Ctx, queries, params.ChannelID)
	if err != nil {
		return ListMembersResult{}, err
	}
	userID := p.user(params.UserID)
	// Anyone else, a pseudonym nobody holds included, is a stranger to a
	// member who may only rename themselves.
	if !managing && userID != params.Principal.UserID {
		return ListMembersResult{}, ErrForbidden
	}
	if _, held := p.byUser[userID]; !held && !slices.Contains(audience, userID) {
		return ListMembersResult{}, ErrMemberNotFound
	}
	p.id(userID)
	if err := p.done(); err != nil {
		return ListMembersResult{}, err
	}
	taken, err := queries.ChatAliasIsUsername(params.Ctx, alias)
	if err != nil {
		return ListMembersResult{}, err
	}
	if taken != 0 {
		return ListMembersResult{}, ErrAliasTaken
	}
	_, err = queries.SetChatChannelPseudonymAlias(params.Ctx, db.SetChatChannelPseudonymAliasParams{
		Alias: alias, ChannelID: params.ChannelID, UserID: userID,
	})
	if sqlutil.IsUniqueConstraintErr(err) {
		return ListMembersResult{}, ErrAliasTaken
	}
	if err != nil {
		return ListMembersResult{}, err
	}
	publish(params.EventBus, params.ChannelID, audience)
	result, err := listMembers(params.Ctx, queries, params.ChannelID, params.DataDir)
	if err != nil {
		return ListMembersResult{}, err
	}
	if err := p.reload(); err != nil {
		return ListMembersResult{}, err
	}
	p.members(&result, managing)
	return result, p.done()
}

// pseudonymsOf is a channel's pseudonyms, nil when it isn't anonymous.
func pseudonymsOf(ctx context.Context, queries db.Querier, channel db.ChatChannel) (*pseudonyms, error) {
	if channel.Anonymous == 0 {
		return nil, nil
	}
	p := &pseudonyms{ctx: ctx, queries: queries, channelID: channel.ID}
	return p, p.reload()
}

// loadPseudonyms is pseudonymsOf for a channel the caller hasn't read. A
// channel that is gone has none.
func loadPseudonyms(ctx context.Context, queries db.Querier, channelID int64) (*pseudonyms, error) {
	channel, err := queries.GetChatChannel(ctx, channelID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return pseudonymsOf(ctx, queries, channel)
}

// newPseudonym gives an account a pseudonym in a channel unless it has one:
// a random negative id inside a JSON number's exact integers, and an alias
// with a random number. Each is drawn again when another account in the
// channel already holds it, or the alias is a username. created is false
// when the account already had one, which the caller reads back. It must not
// run inside a transaction: on PostgreSQL the unique violation a redraw
// follows ends one.
func newPseudonym(ctx context.Context, queries db.Querier, channelID, userID int64) (row db.ChatChannelPseudonym, created bool, err error) {
	for range 8 {
		var id, n *big.Int
		if id, err = rand.Int(rand.Reader, big.NewInt(1<<53-1)); err != nil {
			return row, false, err
		}
		if n, err = rand.Int(rand.Reader, big.NewInt(9000)); err != nil {
			return row, false, err
		}
		row = db.ChatChannelPseudonym{
			ChannelID:   channelID,
			UserID:      userID,
			PseudonymID: -(id.Int64() + 1),
			Alias:       fmt.Sprintf("Anonymous %d", n.Int64()+1000),
		}
		var taken, rows int64
		if taken, err = queries.ChatAliasIsUsername(ctx, row.Alias); err != nil {
			return row, false, err
		}
		if taken != 0 {
			err = errNoFreePseudonym
			continue
		}
		rows, err = queries.CreateChatChannelPseudonym(ctx, db.CreateChatChannelPseudonymParams(row))
		if !sqlutil.IsUniqueConstraintErr(err) {
			return row, rows > 0, err
		}
	}
	return row, false, err
}

// viewChannel fills in what an anonymous channel shows its caller: their own
// pseudonym when they are in it, and the creator's pseudonym in place of the
// account to anyone who isn't privileged.
func viewChannel(ctx context.Context, queries db.Querier, principal accessutil.Principal, channel *Channel) error {
	if !channel.Anonymous {
		return nil
	}
	p, err := loadPseudonyms(ctx, queries, channel.ID)
	if err != nil || p == nil {
		return err
	}
	if channel.Permissions != 0 {
		channel.SelfID = p.id(principal.UserID)
	}
	if !privileged(principal, channel.Permissions) {
		channel.CreatedBy = p.id(channel.CreatedBy)
	}
	return p.done()
}

// viewMessage is a message as its channel's members see it.
func viewMessage(ctx context.Context, queries db.Querier, message Message) (Message, error) {
	p, err := loadPseudonyms(ctx, queries, message.ChannelID)
	if err != nil {
		return Message{}, err
	}
	p.message(&message)
	return message, p.done()
}

// viewReaction is a reaction in channelID as its members see it.
func viewReaction(ctx context.Context, queries db.Querier, channelID int64, reaction Reaction) (Reaction, error) {
	p, err := loadPseudonyms(ctx, queries, channelID)
	if err != nil {
		return Reaction{}, err
	}
	reaction.UserID = p.id(reaction.UserID)
	return reaction, p.done()
}

// viewChannels is viewChannel for each of channels.
func viewChannels(ctx context.Context, queries db.Querier, principal accessutil.Principal, channels []Channel) error {
	for i := range channels {
		if err := viewChannel(ctx, queries, principal, &channels[i]); err != nil {
			return err
		}
	}
	return nil
}

// privileged is whether a caller sees who is behind an anonymous channel's
// pseudonyms: an admin, or a holder of manage_members.
func privileged(principal accessutil.Principal, perms Perms) bool {
	return principal.IsAdmin || perms.Has(PermManageMembers)
}
