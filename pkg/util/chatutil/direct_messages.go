package chatutil

import (
	"context"
	"database/sql"
	"errors"
	"slices"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// The kinds of channel (#2423).
const (
	// KindChannel is a named channel on the server.
	KindChannel = "channel"
	// KindDirect is a direct message: no name, a fixed set of accounts.
	KindDirect = "dm"
)

// MaxDirectMessageMembers caps how many accounts one direct message holds,
// the opener included.
const MaxDirectMessageMembers = 16

var (
	// ErrDirectMessage reports a change a direct message doesn't take:
	// renaming it, deleting it, or adding, changing or removing a member,
	// leaving included. Its people never change under its history.
	ErrDirectMessage = errors.New("a direct message keeps the same people for good; start a new one with the people you want")
	// ErrDirectMessageMembers reports opening a direct message with no one
	// else, or with more accounts than MaxDirectMessageMembers.
	ErrDirectMessageMembers = errors.New("a direct message is with 1 to 15 other people")
)

// OpenDirectMessageParams names the accounts to message.
type OpenDirectMessageParams struct {
	Ctx      context.Context
	Database *db.DatabaseSqlc
	// EventBus hears chat_channel_changed when the direct message is new. Nil
	// skips it.
	EventBus  *eventbus.Bus
	Principal accessutil.Principal
	// UserIDs are the other accounts. The caller is always in it; repeats and
	// the caller's own id are harmless.
	UserIDs []int64
}

// OpenDirectMessageResult is the direct message, and whether this call made
// it.
type OpenDirectMessageResult struct {
	Channel Channel
	Created bool
}

// OpenDirectMessage opens the direct message between the caller and UserIDs
// (#2423): the one these exact accounts already have, or a new one. Its
// members are user rows with the Member set (read, send, react, attach), and
// they never change. Every account must be active
// (accessutil.ErrPrincipalNotFound). The unique dm_key settles two people
// opening the same one at once. A new one publishes chat_channel_changed to
// its members alone; the first member to open it creates its key, as for any
// channel.
func OpenDirectMessage(params OpenDirectMessageParams) (OpenDirectMessageResult, error) {
	if params.Database == nil {
		return OpenDirectMessageResult{}, accessutil.ErrNoDatabase
	}
	if params.Principal.UserID == 0 {
		return OpenDirectMessageResult{}, accessutil.ErrPrincipalNotFound
	}
	members := slices.Compact(slices.Sorted(slices.Values(append([]int64{params.Principal.UserID}, params.UserIDs...))))
	if len(members) < 2 || len(members) > MaxDirectMessageMembers {
		return OpenDirectMessageResult{}, ErrDirectMessageMembers
	}
	queries := params.Database.Queries
	for _, id := range members {
		if err := ensurePrincipal(params.Ctx, queries, id, 0); err != nil {
			return OpenDirectMessageResult{}, err
		}
	}
	key := sql.NullString{String: dmKey(members), Valid: true}
	row, err := queries.GetChatDirectMessage(params.Ctx, key)
	created := errors.Is(err, sql.ErrNoRows)
	if created {
		err = db.InTx(params.Ctx, params.Database.Db, func(q db.Querier) error {
			var err error
			row, err = q.CreateChatDirectMessage(params.Ctx, db.CreateChatDirectMessageParams{
				CreatedBy: sql.NullInt64{Int64: params.Principal.UserID, Valid: true}, DmKey: key,
			})
			if errors.Is(err, sql.ErrNoRows) {
				// Someone opened it first: theirs is committed and complete.
				created = false
				row, err = q.GetChatDirectMessage(params.Ctx, key)
				return err
			}
			if err != nil {
				return err
			}
			for _, id := range members {
				if err := q.SetChatChannelUserMember(params.Ctx, db.SetChatChannelUserMemberParams{
					ChannelID: row.ID, UserID: sql.NullInt64{Int64: id, Valid: true}, Permissions: int64(PresetMember),
				}); err != nil {
					return err
				}
			}
			return nil
		})
	}
	if err != nil {
		return OpenDirectMessageResult{}, err
	}
	perms, err := resolvePerms(params.Ctx, queries, row.ID, params.Principal.UserID)
	if err != nil {
		return OpenDirectMessageResult{}, err
	}
	if perms == 0 {
		return OpenDirectMessageResult{}, ErrChannelNotFound
	}
	channel := channelFromRow(row, perms, true)
	if channel.Members, err = directMembers(params.Ctx, queries, row.ID); err != nil {
		return OpenDirectMessageResult{}, err
	}
	if created {
		announce(params.Ctx, queries, params.EventBus, row.ID, members)
	}
	return OpenDirectMessageResult{Channel: channel, Created: created}, nil
}
