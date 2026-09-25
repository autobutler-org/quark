package chatutil_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"testing"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/avatarutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

type fixture struct {
	database *db.DatabaseSqlc
	bus      *eventbus.Bus
	users    map[string]int64
	everyone int64
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	database := dbtest.NewDB(t)
	f := fixture{database: database, bus: eventbus.New(), users: map[string]int64{}}
	for _, name := range []string{"admin", "bob", "carol", "dave"} {
		user, err := database.Queries.CreateUser(context.Background(), db.CreateUserParams{Username: name, PasswordHash: "h", RecoveryPhraseHash: "r"})
		if err != nil {
			t.Fatal(err)
		}
		f.users[name] = user.ID
	}
	if err := database.Db.QueryRow(`SELECT id FROM groups WHERE name = 'everyone' AND builtin = 1`).Scan(&f.everyone); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f fixture) as(name string) accessutil.Principal {
	return accessutil.Principal{UserID: f.users[name], IsAdmin: name == "admin"}
}

func (f fixture) group(t *testing.T, name string, members ...string) int64 {
	t.Helper()
	group, err := f.database.Queries.CreateGroup(context.Background(), name)
	if err != nil {
		t.Fatal(err)
	}
	for _, member := range members {
		if _, err := f.database.Queries.AddGroupMember(context.Background(), db.AddGroupMemberParams{GroupID: group.ID, UserID: f.users[member]}); err != nil {
			t.Fatal(err)
		}
	}
	return group.ID
}

func (f fixture) create(t *testing.T, as, name string) chatutil.Channel {
	t.Helper()
	result, err := chatutil.CreateChannel(chatutil.CreateChannelParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as), Name: name,
	})
	if err != nil {
		t.Fatalf("CreateChannel(%q) as %s: %v", name, as, err)
	}
	return result.Channel
}

func (f fixture) set(t *testing.T, as string, channelID, userID, groupID int64, level accessutil.Level) error {
	t.Helper()
	_, err := chatutil.SetMember(chatutil.SetMemberParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		ChannelID: channelID, UserID: userID, GroupID: groupID, Level: level,
	})
	return err
}

func (f fixture) remove(as string, channelID, userID, groupID int64) error {
	_, err := chatutil.RemoveMember(chatutil.RemoveMemberParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		ChannelID: channelID, UserID: userID, GroupID: groupID,
	})
	return err
}

// levels maps each channel the account sees to its level there.
func (f fixture) levels(t *testing.T, as string) map[string]string {
	t.Helper()
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: context.Background(), Database: f.database, Principal: f.as(as)})
	if err != nil {
		t.Fatal(err)
	}
	levels := map[string]string{}
	for _, channel := range result.Channels {
		levels[channel.Name] = channel.Level
	}
	return levels
}

func (f fixture) general(t *testing.T) chatutil.Channel {
	t.Helper()
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: context.Background(), Database: f.database, Principal: f.as("bob")})
	if err != nil || len(result.Channels) == 0 {
		t.Fatalf("ListChannels = %+v, %v", result, err)
	}
	return result.Channels[0]
}

func TestGeneralIsSeededForEveryone(t *testing.T) {
	f := newFixture(t)
	general := f.general(t)
	if general.Name != "general" || !general.IsDefault || general.IsPrivate || general.Kind != "channel" || general.Level != "write" {
		t.Errorf("general = %+v", general)
	}
	for _, name := range []string{"admin", "carol"} {
		if got := f.levels(t, name); len(got) != 1 || got["general"] != "write" {
			t.Errorf("%s sees %v, want only general at write", name, got)
		}
	}
}

func TestMembershipThroughGroupsAndLevelPrecedence(t *testing.T) {
	f := newFixture(t)
	design := f.group(t, "design", "carol", "dave")
	channel := f.create(t, "bob", "Design")
	if !channel.IsPrivate || channel.Level != "owner" {
		t.Errorf("created %+v, want private and owned", channel)
	}
	if got := f.levels(t, "carol"); len(got) != 1 {
		t.Fatalf("carol sees %v before being added", got)
	}

	if err := f.set(t, "bob", channel.ID, 0, design, accessutil.Read); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, accessutil.Write); err != nil {
		t.Fatal(err)
	}
	// carol is in by her own row and design's; the better level wins. dave is
	// in through design alone.
	if got := f.levels(t, "carol")["Design"]; got != "write" {
		t.Errorf("carol's level = %q, want write", got)
	}
	if got := f.levels(t, "dave")["Design"]; got != "read" {
		t.Errorf("dave's level = %q, want read", got)
	}
	// Granting everyone read does not lower anyone.
	if err := f.set(t, "bob", channel.ID, 0, f.everyone, accessutil.Read); err != nil {
		t.Fatal(err)
	}
	if got := f.levels(t, "bob")["Design"]; got != "owner" {
		t.Errorf("bob's level = %q, want owner", got)
	}
	if got := f.levels(t, "admin")["Design"]; got != "read" {
		t.Errorf("admin's level through everyone = %q, want read", got)
	}

	resolved, err := chatutil.ResolveMemberUsers(chatutil.ResolveMemberUsersParams{Ctx: context.Background(), Database: f.database, ChannelID: channel.ID})
	if err != nil {
		t.Fatal(err)
	}
	want := []chatutil.ResolvedUser{
		{UserID: f.users["admin"], Username: "admin", Level: accessutil.Read},
		{UserID: f.users["bob"], Username: "bob", Level: accessutil.Owner},
		{UserID: f.users["carol"], Username: "carol", Level: accessutil.Write},
		{UserID: f.users["dave"], Username: "dave", Level: accessutil.Read},
	}
	if !slices.Equal(resolved.Users, want) {
		t.Errorf("ResolveMemberUsers = %+v, want %+v", resolved.Users, want)
	}

	// A disabled account drops out of everyone.
	if _, err := f.database.Queries.SetUserStatus(context.Background(), db.SetUserStatusParams{
		ToStatus: authutil.StatusDisabled, Username: "admin", FromStatus: authutil.StatusActive,
	}); err != nil {
		t.Fatal(err)
	}
	resolved, err = chatutil.ResolveMemberUsers(chatutil.ResolveMemberUsersParams{Ctx: context.Background(), Database: f.database, ChannelID: channel.ID})
	if err != nil || len(resolved.Users) != 3 {
		t.Errorf("ResolveMemberUsers after disabling admin = %+v, %v; want 3 users", resolved.Users, err)
	}
}

func TestNonMemberGetsNothing(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "secret")
	if _, ok := f.levels(t, "carol")["secret"]; ok {
		t.Error("carol lists a channel she isn't in")
	}
	_, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID})
	if !errors.Is(err, chatutil.ErrChannelNotFound) {
		t.Errorf("ListMembers as a non-member = %v, want ErrChannelNotFound", err)
	}
	name := "mine"
	for _, err := range []error{
		func() error {
			_, err := chatutil.UpdateChannel(chatutil.UpdateChannelParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID, Name: &name})
			return err
		}(),
		func() error {
			_, err := chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID})
			return err
		}(),
		f.set(t, "carol", channel.ID, f.users["carol"], 0, accessutil.Owner),
		f.remove("carol", channel.ID, f.users["bob"], 0),
		f.remove("carol", channel.ID, f.users["carol"], 0),
	} {
		if !errors.Is(err, chatutil.ErrChannelNotFound) {
			t.Errorf("change as a non-member = %v, want ErrChannelNotFound", err)
		}
	}
}

func TestMemberWhoIsNotOwnerIsForbidden(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "team")
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, accessutil.Write); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["dave"], 0, accessutil.Read); !errors.Is(err, chatutil.ErrForbidden) {
		t.Errorf("SetMember as a writer = %v, want ErrForbidden", err)
	}
	if err := f.remove("carol", channel.ID, f.users["bob"], 0); !errors.Is(err, chatutil.ErrForbidden) {
		t.Errorf("RemoveMember of another as a writer = %v, want ErrForbidden", err)
	}
	// Anyone may leave.
	if err := f.remove("carol", channel.ID, f.users["carol"], 0); err != nil {
		t.Errorf("carol leaving = %v", err)
	}
	if _, ok := f.levels(t, "carol")["team"]; ok {
		t.Error("carol still lists the channel she left")
	}
}

func TestGeneralIsProtected(t *testing.T) {
	f := newFixture(t)
	general := f.general(t)
	_, err := chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: context.Background(), Database: f.database, Principal: f.as("admin"), ChannelID: general.ID})
	if !errors.Is(err, chatutil.ErrDefaultChannel) {
		t.Errorf("deleting general = %v, want ErrDefaultChannel", err)
	}
	if err := f.remove("admin", general.ID, 0, f.everyone); !errors.Is(err, chatutil.ErrDefaultEveryone) {
		t.Errorf("removing everyone from general = %v, want ErrDefaultEveryone", err)
	}
	if got := f.levels(t, "carol"); got["general"] != "write" {
		t.Errorf("carol sees %v after the refusals", got)
	}
}

func TestAdminManagesWithoutSeeing(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "private")
	if _, ok := f.levels(t, "admin")["private"]; ok {
		t.Error("admin lists a channel they aren't in")
	}

	name := "renamed"
	updated, err := chatutil.UpdateChannel(chatutil.UpdateChannelParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as("admin"), ChannelID: channel.ID, Name: &name,
	})
	if err != nil || updated.Channel.Name != "renamed" || updated.Channel.Level != "" || !updated.Channel.IsPrivate {
		t.Errorf("admin rename = %+v, %v", updated.Channel, err)
	}
	members, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: context.Background(), Database: f.database, Principal: f.as("admin"), ChannelID: channel.ID})
	if err != nil || len(members.Members) != 1 || members.Members[0].UserID != f.users["bob"] || members.Members[0].Level != "owner" {
		t.Errorf("admin ListMembers = %+v, %v", members, err)
	}
	if err := f.set(t, "admin", channel.ID, f.users["carol"], 0, accessutil.Read); err != nil {
		t.Errorf("admin SetMember = %v", err)
	}
	if _, ok := f.levels(t, "admin")["renamed"]; ok {
		t.Error("managing a channel made admin a member")
	}
	if _, err := chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: context.Background(), Database: f.database, Principal: f.as("admin"), ChannelID: channel.ID}); err != nil {
		t.Errorf("admin DeleteChannel = %v", err)
	}
	if _, ok := f.levels(t, "bob")["renamed"]; ok {
		t.Error("bob still lists the deleted channel")
	}
}

func TestNamesAndPrincipals(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "  Plans  ")
	if channel.Name != "Plans" {
		t.Errorf("name = %q, want it trimmed", channel.Name)
	}
	for _, tc := range []struct {
		name string
		want error
	}{
		{"plans", chatutil.ErrNameTaken},
		{"GENERAL", chatutil.ErrNameTaken},
		{"   ", chatutil.ErrInvalidName},
		{"a\nb", chatutil.ErrInvalidName},
	} {
		_, err := chatutil.CreateChannel(chatutil.CreateChannelParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), Name: tc.name})
		if !errors.Is(err, tc.want) {
			t.Errorf("CreateChannel(%q) = %v, want %v", tc.name, err, tc.want)
		}
	}
	if err := f.set(t, "bob", channel.ID, 999, 0, accessutil.Read); !errors.Is(err, accessutil.ErrPrincipalNotFound) {
		t.Errorf("SetMember of a missing account = %v", err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], f.everyone, accessutil.Read); !errors.Is(err, accessutil.ErrGrantTarget) {
		t.Errorf("SetMember of both kinds = %v", err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, accessutil.None); !errors.Is(err, accessutil.ErrInvalidLevel) {
		t.Errorf("SetMember at None = %v", err)
	}
	if err := f.remove("bob", channel.ID, f.users["carol"], 0); !errors.Is(err, chatutil.ErrMemberNotFound) {
		t.Errorf("RemoveMember of a non-member = %v", err)
	}
}

func TestListMembersExpandsGroupsWithAvatars(t *testing.T) {
	f := newFixture(t)
	dataDir := t.TempDir()
	if err := os.MkdirAll(avatarutil.Dir(dataDir), 0o755); err != nil {
		t.Fatal(err)
	}
	picture := filepath.Join(avatarutil.Dir(dataDir), strconv.FormatInt(f.users["carol"], 10)+".jpg")
	if err := os.WriteFile(picture, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	stamp := time.UnixMilli(1_700_000_000_000)
	if err := os.Chtimes(picture, stamp, stamp); err != nil {
		t.Fatal(err)
	}
	design := f.group(t, "design", "carol", "dave")
	channel := f.create(t, "bob", "design")
	if err := f.set(t, "bob", channel.ID, 0, design, accessutil.Read); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, accessutil.Write); err != nil {
		t.Fatal(err)
	}

	result, err := chatutil.ListMembers(chatutil.ListMembersParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("dave"), ChannelID: channel.ID, DataDir: dataDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []chatutil.Member{
		{GroupID: design, Name: "design", Level: "read", Users: []chatutil.MemberUser{
			{ID: f.users["carol"], Username: "carol", AvatarUpdatedAt: stamp.UnixMilli()},
			{ID: f.users["dave"], Username: "dave"},
		}},
		{UserID: f.users["bob"], Name: "bob", Level: "owner"},
		{UserID: f.users["carol"], Name: "carol", Level: "write", AvatarUpdatedAt: stamp.UnixMilli()},
	}
	if len(result.Members) != len(want) {
		t.Fatalf("ListMembers = %+v, want %+v", result.Members, want)
	}
	for i := range want {
		got := result.Members[i]
		if got.UserID != want[i].UserID || got.GroupID != want[i].GroupID || got.Name != want[i].Name ||
			got.Level != want[i].Level || got.AvatarUpdatedAt != want[i].AvatarUpdatedAt || !slices.Equal(got.Users, want[i].Users) {
			t.Errorf("member %d = %+v, want %+v", i, got, want[i])
		}
	}
}

func TestChangesTellMembersBeforeAndAfter(t *testing.T) {
	f := newFixture(t)
	events, unsub := f.bus.Subscribe("chat-test")
	defer unsub()
	next := func() eventbus.ChatChannelChanged {
		t.Helper()
		select {
		case evt := <-events:
			changed, ok := evt.Data.(eventbus.ChatChannelChanged)
			if evt.Kind != eventbus.EventChatChannelChanged || !ok {
				t.Fatalf("event = %+v", evt)
			}
			return changed
		default:
			t.Fatal("no chat_channel_changed event")
			return eventbus.ChatChannelChanged{}
		}
	}
	has := func(changed eventbus.ChatChannelChanged, names ...string) {
		t.Helper()
		for _, name := range names {
			if !slices.Contains(changed.Audience, f.users[name]) {
				t.Errorf("audience %v is missing %s", changed.Audience, name)
			}
		}
		if slices.Contains(changed.Audience, f.users["dave"]) {
			t.Errorf("audience %v holds dave, who was never a member", changed.Audience)
		}
	}

	channel := f.create(t, "bob", "news")
	has(next(), "bob")
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, accessutil.Read); err != nil {
		t.Fatal(err)
	}
	has(next(), "bob", "carol")
	if err := f.remove("bob", channel.ID, f.users["carol"], 0); err != nil {
		t.Fatal(err)
	}
	has(next(), "bob", "carol")
	if _, err := chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as("bob"), ChannelID: channel.ID}); err != nil {
		t.Fatal(err)
	}
	if changed := next(); changed.ChannelID != channel.ID {
		t.Errorf("delete event = %+v", changed)
	} else {
		has(changed, "bob")
	}
}

func TestLastOwnerCannotLeaveOrBeDemotedExceptByAnAdmin(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "design")
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, accessutil.Write); err != nil {
		t.Fatal(err)
	}

	if err := f.remove("bob", channel.ID, f.users["bob"], 0); !errors.Is(err, chatutil.ErrLastOwner) {
		t.Errorf("last owner leaving = %v, want ErrLastOwner", err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["bob"], 0, accessutil.Write); !errors.Is(err, chatutil.ErrLastOwner) {
		t.Errorf("last owner demoting themselves = %v, want ErrLastOwner", err)
	}
	if got := f.levels(t, "bob")["design"]; got != "owner" {
		t.Errorf("after refusals bob is %q, want owner: the change must roll back", got)
	}

	// A second owner, even through a group, lets the first one go.
	crew := f.group(t, "crew", "carol")
	if err := f.set(t, "bob", channel.ID, 0, crew, accessutil.Owner); err != nil {
		t.Fatal(err)
	}
	if err := f.remove("bob", channel.ID, f.users["bob"], 0); err != nil {
		t.Errorf("leaving with another owner = %v", err)
	}
	if err := f.remove("carol", channel.ID, 0, crew); !errors.Is(err, chatutil.ErrLastOwner) {
		t.Errorf("removing the group holding the last owner = %v, want ErrLastOwner", err)
	}

	// An admin may leave a channel ownerless.
	if err := f.remove("admin", channel.ID, 0, crew); err != nil {
		t.Errorf("admin removing the last owner = %v", err)
	}
	// With no owner left, a writer may still leave.
	if err := f.remove("carol", channel.ID, f.users["carol"], 0); err != nil {
		t.Errorf("writer leaving an ownerless channel = %v", err)
	}
}

func TestListingEveryChannelIsForAdmins(t *testing.T) {
	f := newFixture(t)
	f.create(t, "bob", "secret")
	ctx := context.Background()

	if _, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: ctx, Database: f.database, Principal: f.as("bob"), All: true}); !errors.Is(err, chatutil.ErrAdminOnly) {
		t.Errorf("All for bob = %v, want ErrAdminOnly", err)
	}
	if got := f.levels(t, "admin"); len(got) != 1 || got["general"] != "write" {
		t.Errorf("admin's own channels = %v, want only general", got)
	}
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: ctx, Database: f.database, Principal: f.as("admin"), All: true})
	if err != nil {
		t.Fatal(err)
	}
	var names, levels []string
	for _, c := range result.Channels {
		names, levels = append(names, c.Name), append(levels, c.Level)
	}
	if !slices.Equal(names, []string{"general", "secret"}) || !slices.Equal(levels, []string{"write", ""}) {
		t.Errorf("All for admin = %v %v, want general then secret with no level", names, levels)
	}
	if !result.Channels[1].IsPrivate {
		t.Errorf("secret = %+v, want private", result.Channels[1])
	}
}
