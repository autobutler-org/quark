package v0_chat

import "github.com/autobutler-org/quark/pkg/util/serverutil"

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
	Permissions []string `json:"permissions" enums:"read_messages,send_messages,add_reactions,delete_messages,manage_channel,manage_members"`
}

// removeMemberBody removes one account's or group's row from a channel.
// Exactly one of userId and groupId is set.
type removeMemberBody struct {
	UserID  int64 `json:"userId,omitempty"`
	GroupID int64 `json:"groupId,omitempty"`
}
