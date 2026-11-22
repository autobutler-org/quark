package chatutil

import (
	"context"
	"io"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
)

// keyState is a channel's key versions against its members, the ground truth
// for pending grants and rotation (#2417).
type keyState struct {
	// current is the newest version, 0 before any.
	current  int64
	versions []KeyVersion
	// members are the active accounts the channel's rows reach with
	// read_messages, the only ones entitled to the key.
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
	// Permissions is the set a member_set gave; absent from member_removed.
	Permissions Perms `json:"permissions,omitempty"`
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

// attachmentReader counts the bytes of an upload as they are read, and fails
// with ErrAttachmentTooLarge on the read that passes MaxAttachmentBytes, so an
// oversized upload fails before it is committed to its final path.
type attachmentReader struct {
	r io.Reader
	n int64
}

func (a *attachmentReader) Read(p []byte) (int, error) {
	n, err := a.r.Read(p)
	a.n += int64(n)
	if a.n > MaxAttachmentBytes {
		return n, ErrAttachmentTooLarge
	}
	return n, err
}

// pseudonyms are the per-channel pseudonyms of an anonymous channel (#2949),
// and the one place a real account id is swapped for one. A nil *pseudonyms
// is any other channel, and every method on it leaves ids as they are.
//
// Crypto-bound ids (a reaction's or answer's additional data, a grant's
// recipient, an event's actor) are pseudonyms for every viewer, privileged or
// not, so one ciphertext or signature verifies for everyone. Only the member
// list tells a privileged viewer who is behind each one.
//
// A pseudonym is made the first time it is needed, so err holds the first
// write that failed; callers check it once with done.
type pseudonyms struct {
	ctx       context.Context
	queries   db.Querier
	channelID int64
	byUser    map[int64]db.ChatChannelPseudonym
	byID      map[int64]int64
	err       error
}

// id is the pseudonym of an account, made if it has none. 0 stays 0.
func (p *pseudonyms) id(userID int64) int64 {
	if p == nil || userID == 0 {
		return userID
	}
	if row, ok := p.byUser[userID]; ok {
		return row.PseudonymID
	}
	if p.err != nil {
		return 0
	}
	row, created, err := newPseudonym(p.ctx, p.queries, p.channelID, userID)
	if p.err = err; err != nil {
		return 0
	}
	if !created {
		// Someone else made it first: read theirs.
		if p.err = p.reload(); p.err != nil {
			return 0
		}
		row = p.byUser[userID]
	}
	p.byUser[userID], p.byID[row.PseudonymID] = row, userID
	return row.PseudonymID
}

// alias is the name an account goes by in the channel.
func (p *pseudonyms) alias(userID int64) string {
	p.id(userID)
	return p.byUser[userID].Alias
}

// user is the account behind an id a client sent: a pseudonym is looked up,
// and anything else is returned as it is. A pseudonym nobody holds stays the
// negative id it was, which names no account.
func (p *pseudonyms) user(id int64) int64 {
	if p == nil {
		return id
	}
	if account, ok := p.byID[id]; ok {
		return account
	}
	return id
}

// done is the first error making a pseudonym hit.
func (p *pseudonyms) done() error {
	if p == nil {
		return nil
	}
	return p.err
}

// reload reads the channel's pseudonyms again.
func (p *pseudonyms) reload() error {
	rows, err := p.queries.ListChatChannelPseudonyms(p.ctx, p.channelID)
	if err != nil {
		return err
	}
	p.byUser = make(map[int64]db.ChatChannelPseudonym, len(rows))
	p.byID = make(map[int64]int64, len(rows))
	for _, row := range rows {
		p.byUser[row.UserID] = row
		p.byID[row.PseudonymID] = row.UserID
	}
	return nil
}

// message swaps the author, and the account on each reaction and answer.
func (p *pseudonyms) message(m *Message) {
	if p == nil {
		return
	}
	m.AuthorID = p.id(m.AuthorID)
	for i := range m.Reactions {
		m.Reactions[i].UserID = p.id(m.Reactions[i].UserID)
	}
	if m.Poll != nil {
		for i := range m.Poll.Answers {
			m.Poll.Answers[i].UserID = p.id(m.Poll.Answers[i].UserID)
		}
	}
}

// keys swaps who created each version and who granted and received each
// grant.
func (p *pseudonyms) keys(versions []KeyVersion, grants []KeyGrant) {
	if p == nil {
		return
	}
	for i := range versions {
		versions[i].CreatedBy = p.id(versions[i].CreatedBy)
	}
	for i := range grants {
		grants[i].UserID = p.id(grants[i].UserID)
		grants[i].GrantedBy = p.id(grants[i].GrantedBy)
	}
}

// members shows a channel's rows to a viewer. A privileged viewer gets every
// account's pseudonym and alias beside it, in groups too. Anyone else gets no
// group's users, since a group of one, or the groups a pseudonym sits in, would
// unmask it: the group rows come first, in the order they came, with no users,
// then every active account the rows reach as an account row under its
// pseudonym and alias, with its effective set and no profile picture, by
// alias, so neither the order nor a missing row says anything about accounts.
func (p *pseudonyms) members(result *ListMembersResult, privileged bool) {
	if p == nil {
		return
	}
	if privileged {
		for i := range result.Members {
			m := &result.Members[i]
			if m.UserID != 0 {
				m.PseudonymID, m.Alias = p.id(m.UserID), p.alias(m.UserID)
			}
			for j := range m.Users {
				u := &m.Users[j]
				u.PseudonymID, u.Alias = p.id(u.ID), p.alias(u.ID)
			}
		}
	} else {
		users, err := memberUsers(p.ctx, p.queries, p.channelID)
		if err != nil && p.err == nil {
			p.err = err
		}
		members := make([]Member, 0, len(result.Members)+len(users))
		for _, m := range result.Members {
			if m.GroupID != 0 {
				m.Users = nil
				members = append(members, m)
			}
		}
		groups := len(members)
		for _, u := range users {
			id, alias := p.id(u.UserID), p.alias(u.UserID)
			members = append(members, Member{UserID: id, Name: alias, Permissions: u.Perms, PseudonymID: id, Alias: alias})
		}
		slices.SortFunc(members[groups:], func(a, b Member) int {
			return strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
		})
		result.Members = members
	}
	if result.Event != nil {
		result.Event.ActorID = p.id(result.Event.ActorID)
	}
}
