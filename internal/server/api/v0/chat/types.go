package v0_chat

import (
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

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
		listChannelEventsRoute,
		signChannelEventRoute,
		postMessageRoute,
		listMessagesRoute,
		deleteMessageRoute,
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

// setMemberBody gives one account or group a level on a channel. Exactly one
// of userId and groupId is set.
type setMemberBody struct {
	UserID  int64 `json:"userId,omitempty"`
	GroupID int64 `json:"groupId,omitempty"`
	// Level is read, write or owner.
	Level string `json:"level"`
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
