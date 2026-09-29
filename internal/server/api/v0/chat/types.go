package v0_chat

import (
	"errors"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

// errTooManyRequests is a rate-limited chat write's error, written for the
// app to show like chatutil's sentinels.
var errTooManyRequests = errors.New("you're sending these too quickly; wait a moment and try again")

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		listChannelsRoute,
		createChannelRoute,
		updateChannelRoute,
		deleteChannelRoute,
		listMembersRoute,
		setMemberRoute,
		removeMemberRoute,
		getMyKeysRoute,
		putMyKeysRoute,
		getUserKeysRoute,
		getChannelKeysRoute,
		createKeyVersionRoute,
		listPendingGrantsRoute,
		uploadGrantsRoute,
		deleteKeyGrantRoute,
		listChannelEventsRoute,
		signChannelEventRoute,
		postMessageRoute,
		listMessagesRoute,
		deleteMessageRoute,
		addReactionRoute,
		deleteReactionRoute,
	}
}

// createChannelBody names a new channel.
type createChannelBody struct {
	Name  string `json:"name"`
	Topic string `json:"topic"`
}

// updateChannelBody changes a channel's name, topic or both. A field left out
// is unchanged.
type updateChannelBody struct {
	Name  *string `json:"name,omitempty"`
	Topic *string `json:"topic,omitempty"`
}

// setMemberBody gives one account or group a set of permissions on a
// channel. Exactly one of userId and groupId is set.
type setMemberBody struct {
	UserID  int64 `json:"userId,omitempty"`
	GroupID int64 `json:"groupId,omitempty"`
	// Permissions is the whole set the row carries, by name.
	Permissions []string `json:"permissions" enums:"read_messages,send_messages,add_reactions,delete_messages,manage_channel,manage_members,manage_reactions"`
}

// removeMemberBody removes one account's or group's row from a channel.
// Exactly one of userId and groupId is set.
type removeMemberBody struct {
	UserID  int64 `json:"userId,omitempty"`
	GroupID int64 `json:"groupId,omitempty"`
}

// createKeyVersionBody is the next key version and the caller's grant of it.
// Byte fields are base64.
type createKeyVersionBody struct {
	Version   int64  `json:"version"`
	SealedKey []byte `json:"sealedKey"`
	Signature []byte `json:"signature"`
}

// uploadGrantsBody is grants the caller sealed and signed.
type uploadGrantsBody struct {
	Grants []chatutil.GrantUpload `json:"grants"`
}

// signEventBody is the caller's signature over an event, base64.
type signEventBody struct {
	Signature []byte `json:"signature"`
}

// postMessageBody is a message the caller's client encrypted. Ciphertext is
// base64 nonce || XChaCha20-Poly1305 output.
type postMessageBody struct {
	Ciphertext []byte `json:"ciphertext"`
	KeyVersion int64  `json:"keyVersion"`
}

// reactionBody is a reaction the caller's client encrypted. Ciphertext is
// base64 nonce || XChaCha20-Poly1305 output.
type reactionBody struct {
	Ciphertext []byte `json:"ciphertext"`
	KeyVersion int64  `json:"keyVersion"`
}
