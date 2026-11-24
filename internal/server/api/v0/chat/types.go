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
		openDirectMessageRoute,
		updateChannelRoute,
		deleteChannelRoute,
		listMembersRoute,
		setMemberRoute,
		setMemberAliasRoute,
		removeMemberRoute,
		getMyKeysRoute,
		putMyKeysRoute,
		getUserKeysRoute,
		getChannelKeysRoute,
		putMyChannelKeysRoute,
		createKeyVersionRoute,
		regenerateKeyVersionRoute,
		listPendingGrantsRoute,
		uploadGrantsRoute,
		deleteKeyGrantRoute,
		listChannelEventsRoute,
		signChannelEventRoute,
		postMessageRoute,
		putAttachmentRoute,
		getAttachmentRoute,
		listMessagesRoute,
		listRepliesRoute,
		editMessageRoute,
		deleteMessageRoute,
		markReadRoute,
		markBranchReadRoute,
		postTypingRoute,
		addReactionRoute,
		deleteReactionRoute,
		answerPollRoute,
		listPollAnswersRoute,
		closePollRoute,
	}
}

// createChannelBody names a new channel. Anonymous makes it an anonymous
// channel (#2949), which it stays.
type createChannelBody struct {
	Name      string `json:"name"`
	Topic     string `json:"topic"`
	Anonymous bool   `json:"anonymous,omitempty"`
}

// openDirectMessageBody names the other accounts in a direct message.
type openDirectMessageBody struct {
	UserIDs []int64 `json:"userIds"`
	// FromChannelID is the direct message the caller is adding people to,
	// which marks a new one as forked from it.
	FromChannelID int64 `json:"fromChannelId,omitempty"`
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
	Permissions []string `json:"permissions" enums:"read_messages,send_messages,add_reactions,delete_messages,manage_channel,manage_members,manage_reactions,attach_files,mention_everyone"`
}

// setMemberAliasBody renames one account's pseudonym in an anonymous
// channel. userId is the account's id or its pseudonym.
type setMemberAliasBody struct {
	UserID int64  `json:"userId"`
	Alias  string `json:"alias"`
}

// putMyChannelKeysBody is the public keys the caller's app derived for one
// anonymous channel. Byte fields are base64.
type putMyChannelKeysBody struct {
	BoxPublicKey  []byte `json:"boxPublicKey"`
	SignPublicKey []byte `json:"signPublicKey"`
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
// base64 nonce || XChaCha20-Poly1305 output. ClientMessageID is optional, the
// client's own id for this send, kept the same across its retries (#3531).
// Poll, when set, makes the message a poll with those settings (#3893).
// AttachmentIDs names ciphertext already uploaded to the channel, bound to
// this message. RootID, when set, posts it as a reply in that channel
// message's side conversation (#4345).
type postMessageBody struct {
	Ciphertext      []byte                 `json:"ciphertext"`
	KeyVersion      int64                  `json:"keyVersion"`
	ClientMessageID string                 `json:"clientMessageId,omitempty"`
	AttachmentIDs   []string               `json:"attachmentIds,omitempty"`
	RootID          int64                  `json:"rootId,omitempty"`
	Poll            *chatutil.PollSettings `json:"poll,omitempty"`
}

// editMessageBody is the new ciphertext of a message, encrypted by its
// author's client. Ciphertext is base64 nonce || XChaCha20-Poly1305 output.
type editMessageBody struct {
	Ciphertext []byte `json:"ciphertext"`
	KeyVersion int64  `json:"keyVersion"`
}

// markReadBody names the newest message the caller has read in a channel.
type markReadBody struct {
	MessageID int64 `json:"messageId"`
}

// pollAnswerBody is a poll answer the caller's client padded to 4 KiB and
// encrypted. Ciphertext is base64 nonce || XChaCha20-Poly1305 output.
type pollAnswerBody struct {
	Ciphertext []byte `json:"ciphertext"`
	KeyVersion int64  `json:"keyVersion"`
}

// reactionBody is a reaction the caller's client encrypted. Ciphertext is
// base64 nonce || XChaCha20-Poly1305 output.
type reactionBody struct {
	Ciphertext []byte `json:"ciphertext"`
	KeyVersion int64  `json:"keyVersion"`
}
