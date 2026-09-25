package chatutil

import "slices"

// keyState is a channel's key versions against its members, the ground truth
// for pending grants and rotation (#2417).
type keyState struct {
	// current is the newest version, 0 before any.
	current  int64
	versions []KeyVersion
	// members are the active accounts the channel's rows reach.
	members map[int64]bool
	// boxKeys are the members with published chat keys, by account.
	boxKeys map[int64][]byte
	// holders maps a version to the accounts holding a grant of it.
	holders map[int64]map[int64]bool
	// strangers is whether a current-version grant belongs to an account that
	// is no longer an active member, or was deleted.
	strangers bool
}

// memberEventPayload is a member_set or member_removed event's payload.
type memberEventPayload struct {
	UserID  int64  `json:"userId,omitempty"`
	GroupID int64  `json:"groupId,omitempty"`
	Name    string `json:"name"`
	Level   string `json:"level,omitempty"`
}

// keyEventPayload is a key_created event's payload.
type keyEventPayload struct {
	Version int64 `json:"version"`
}

// rotationNeeded is whether someone outside the channel holds its current
// key, so the next message needs a new one.
func (s keyState) rotationNeeded() bool {
	return s.current > 0 && s.strangers
}

// pending lists every member with published keys who lacks a version, by
// version then account. New members get every version, so they see history.
func (s keyState) pending() []PendingGrant {
	users := make([]int64, 0, len(s.boxKeys))
	for id := range s.boxKeys {
		users = append(users, id)
	}
	slices.Sort(users)
	pending := []PendingGrant{}
	for _, v := range s.versions {
		for _, id := range users {
			if !s.holders[v.Version][id] {
				pending = append(pending, PendingGrant{Version: v.Version, UserID: id, BoxPublicKey: s.boxKeys[id]})
			}
		}
	}
	return pending
}

// keyHolders are the members holding any version, who can fill a grant.
func (s keyState) keyHolders() []int64 {
	seen := map[int64]bool{}
	holders := []int64{}
	for _, v := range s.versions {
		for id := range s.holders[v.Version] {
			if !seen[id] {
				seen[id] = true
				holders = append(holders, id)
			}
		}
	}
	slices.Sort(holders)
	return holders
}
