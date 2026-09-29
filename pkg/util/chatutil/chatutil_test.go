package chatutil_test

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
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
	// fills is each account's sampleKeys fill, set by publishKeys, which
	// names the key its grants are signed with.
	fills    map[string]byte
	everyone int64
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	database := dbtest.NewDB(t)
	f := fixture{database: database, bus: eventbus.New(), users: map[string]int64{}, fills: map[string]byte{}}
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

func (f fixture) set(t *testing.T, as string, channelID, userID, groupID int64, perms chatutil.Perms) error {
	t.Helper()
	_, err := chatutil.SetMember(chatutil.SetMemberParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		ChannelID: channelID, UserID: userID, GroupID: groupID, Permissions: perms,
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

// perms maps each channel the account sees to its effective set there.
func (f fixture) perms(t *testing.T, as string) map[string]chatutil.Perms {
	t.Helper()
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: context.Background(), Database: f.database, Principal: f.as(as)})
	if err != nil {
		t.Fatal(err)
	}
	perms := map[string]chatutil.Perms{}
	for _, channel := range result.Channels {
		perms[channel.Name] = channel.Permissions
	}
	return perms
}

func (f fixture) resolve(t *testing.T, as string, channelID int64) chatutil.Perms {
	t.Helper()
	result, err := chatutil.ResolvePerms(chatutil.ResolvePermsParams{
		Ctx: context.Background(), Database: f.database, ChannelID: channelID, Principal: f.as(as),
	})
	if err != nil {
		t.Fatal(err)
	}
	return result.Perms
}

func (f fixture) general(t *testing.T) chatutil.Channel {
	t.Helper()
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: context.Background(), Database: f.database, Principal: f.as("bob")})
	if err != nil || len(result.Channels) == 0 {
		t.Fatalf("ListChannels = %+v, %v", result, err)
	}
	return result.Channels[0]
}

func TestPermsParseAndString(t *testing.T) {
	for p := chatutil.Perms(0); p <= chatutil.PermsAll; p++ {
		got, err := chatutil.ParsePerms(p.Names())
		if err != nil || got != p {
			t.Errorf("ParsePerms(%v) = %v, %v; want %v", p.Names(), got, err, p)
		}
	}
	all := chatutil.PermsAll.String()
	if want := "read_messages,send_messages,add_reactions,delete_messages,manage_channel,manage_members,manage_reactions"; all != want {
		t.Errorf("PermsAll.String() = %q, want %q", all, want)
	}
	if got := chatutil.Perms(0).Names(); got == nil || len(got) != 0 {
		t.Errorf("empty Names() = %#v, want an empty, non-nil list", got)
	}
	for _, name := range []string{"view_channel", "READ_MESSAGES", ""} {
		if _, err := chatutil.ParsePerms([]string{"read_messages", name}); !errors.Is(err, chatutil.ErrInvalidPerms) {
			t.Errorf("ParsePerms(%q) = %v, want ErrInvalidPerms", name, err)
		}
	}

	body, err := json.Marshal(chatutil.PresetMember)
	if err != nil || string(body) != `["read_messages","send_messages","add_reactions"]` {
		t.Errorf("Member as JSON = %s, %v", body, err)
	}
	var back chatutil.Perms
	if err := json.Unmarshal(body, &back); err != nil || back != chatutil.PresetMember {
		t.Errorf("Member back from JSON = %v, %v", back, err)
	}
	if err := json.Unmarshal([]byte(`["pin_messages"]`), &back); !errors.Is(err, chatutil.ErrInvalidPerms) {
		t.Errorf("unmarshal of an unknown name = %v", err)
	}
}

func TestPermsValidate(t *testing.T) {
	for _, tc := range []struct {
		perms   chatutil.Perms
		missing string
	}{
		{chatutil.PermSendMessages, "send_messages needs read_messages"},
		{chatutil.PermAddReactions, "add_reactions needs read_messages"},
		{chatutil.PermDeleteMessages | chatutil.PermManageMembers, "delete_messages needs read_messages"},
		{chatutil.PermManageReactions, "manage_reactions needs read_messages"},
		{1 << 40, "unknown permission bits"},
	} {
		err := tc.perms.Validate()
		if !errors.Is(err, chatutil.ErrInvalidPerms) || !strings.Contains(err.Error(), tc.missing) {
			t.Errorf("Validate(%v) = %v, want ErrInvalidPerms naming %q", tc.perms, err, tc.missing)
		}
	}
	for _, perms := range []chatutil.Perms{
		0,
		chatutil.PermReadMessages,
		chatutil.PermManageMembers,
		chatutil.PermManageChannel,
		chatutil.PermManageChannel | chatutil.PermManageMembers,
		chatutil.PermReadMessages | chatutil.PermDeleteMessages,
		chatutil.PermsAll,
	} {
		if err := perms.Validate(); err != nil {
			t.Errorf("Validate(%v) = %v, want coherent", perms, err)
		}
	}
}

func TestPresets(t *testing.T) {
	read, send, react := chatutil.PermReadMessages, chatutil.PermSendMessages, chatutil.PermAddReactions
	del, channel, members := chatutil.PermDeleteMessages, chatutil.PermManageChannel, chatutil.PermManageMembers
	reactions := chatutil.PermManageReactions
	for _, tc := range []struct {
		name string
		got  chatutil.Perms
		want chatutil.Perms
	}{
		{"viewer", chatutil.PresetViewer, read},
		{"member", chatutil.PresetMember, read | send | react},
		{"moderator", chatutil.PresetModerator, read | send | react | del | reactions | members},
		{"owner", chatutil.PresetOwner, read | send | react | del | reactions | channel | members},
		{"all", chatutil.PermsAll, chatutil.PresetOwner},
	} {
		if tc.got != tc.want {
			t.Errorf("%s = %v, want %v", tc.name, tc.got, tc.want)
		}
		if err := tc.got.Validate(); err != nil {
			t.Errorf("%s is incoherent: %v", tc.name, err)
		}
	}
}

func TestGeneralIsSeededForEveryone(t *testing.T) {
	f := newFixture(t)
	general := f.general(t)
	if general.Name != "general" || !general.IsDefault || general.IsPrivate || general.Kind != "channel" || general.Permissions != chatutil.PresetMember {
		t.Errorf("general = %+v", general)
	}
	for _, name := range []string{"admin", "carol"} {
		if got := f.perms(t, name); len(got) != 1 || got["general"] != chatutil.PresetMember {
			t.Errorf("%s sees %v, want only general as a Member", name, got)
		}
	}
}

func TestResolvePermsUnionsEveryRow(t *testing.T) {
	f := newFixture(t)
	design := f.group(t, "design", "carol", "dave")
	mods := f.group(t, "mods", "carol")
	channel := f.create(t, "bob", "Design")
	if !channel.IsPrivate || channel.Permissions != chatutil.PermsAll {
		t.Errorf("created %+v, want private with every permission", channel)
	}
	if got := f.resolve(t, "carol", channel.ID); got != 0 {
		t.Fatalf("carol before being added = %v, want the empty set", got)
	}
	if got := f.resolve(t, "carol", 9999); got != 0 {
		t.Errorf("a missing channel = %v, want the empty set", got)
	}

	for _, row := range []struct {
		userID, groupID int64
		perms           chatutil.Perms
	}{
		{0, f.everyone, chatutil.PresetViewer},
		{0, design, chatutil.PermReadMessages | chatutil.PermSendMessages},
		{0, mods, chatutil.PermManageMembers},
		{f.users["carol"], 0, chatutil.PermReadMessages | chatutil.PermAddReactions},
	} {
		if err := f.set(t, "bob", channel.ID, row.userID, row.groupID, row.perms); err != nil {
			t.Fatal(err)
		}
	}
	// carol has her own row, two groups' and everyone's: the union.
	want := chatutil.PermReadMessages | chatutil.PermSendMessages | chatutil.PermAddReactions | chatutil.PermManageMembers
	if got := f.resolve(t, "carol", channel.ID); got != want {
		t.Errorf("carol = %v, want %v", got, want)
	}
	if got := f.perms(t, "carol")["Design"]; got != want {
		t.Errorf("carol's listed set = %v, want %v", got, want)
	}
	if got := f.resolve(t, "dave", channel.ID); got != chatutil.PermReadMessages|chatutil.PermSendMessages {
		t.Errorf("dave through design and everyone = %v", got)
	}
	if got := f.resolve(t, "admin", channel.ID); got != chatutil.PresetViewer {
		t.Errorf("admin through everyone alone = %v, want Viewer", got)
	}
	if got := f.resolve(t, "bob", channel.ID); got != chatutil.PermsAll {
		t.Errorf("bob = %v, want every permission", got)
	}

	resolved, err := chatutil.ResolveMemberUsers(chatutil.ResolveMemberUsersParams{Ctx: context.Background(), Database: f.database, ChannelID: channel.ID})
	if err != nil {
		t.Fatal(err)
	}
	wantUsers := []chatutil.ResolvedUser{
		{UserID: f.users["admin"], Username: "admin", Perms: chatutil.PresetViewer},
		{UserID: f.users["bob"], Username: "bob", Perms: chatutil.PermsAll},
		{UserID: f.users["carol"], Username: "carol", Perms: want},
		{UserID: f.users["dave"], Username: "dave", Perms: chatutil.PermReadMessages | chatutil.PermSendMessages},
	}
	if !slices.Equal(resolved.Users, wantUsers) {
		t.Errorf("ResolveMemberUsers = %+v, want %+v", resolved.Users, wantUsers)
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
	if _, ok := f.perms(t, "carol")["secret"]; ok {
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
		f.set(t, "carol", channel.ID, f.users["carol"], 0, chatutil.PermsAll),
		f.remove("carol", channel.ID, f.users["bob"], 0),
		f.remove("carol", channel.ID, f.users["carol"], 0),
	} {
		if !errors.Is(err, chatutil.ErrChannelNotFound) {
			t.Errorf("change as a non-member = %v, want ErrChannelNotFound", err)
		}
	}
}

func TestMemberWithoutManageIsForbidden(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "team")
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["dave"], 0, chatutil.PresetViewer); !errors.Is(err, chatutil.ErrForbidden) {
		t.Errorf("SetMember without manage_members = %v, want ErrForbidden", err)
	}
	if err := f.remove("carol", channel.ID, f.users["bob"], 0); !errors.Is(err, chatutil.ErrForbidden) {
		t.Errorf("RemoveMember of another without manage_members = %v, want ErrForbidden", err)
	}
	name := "ours"
	if _, err := chatutil.UpdateChannel(chatutil.UpdateChannelParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID, Name: &name}); !errors.Is(err, chatutil.ErrForbidden) {
		t.Errorf("UpdateChannel without manage_channel = %v, want ErrForbidden", err)
	}
	// Anyone may leave.
	if err := f.remove("carol", channel.ID, f.users["carol"], 0); err != nil {
		t.Errorf("carol leaving = %v", err)
	}
	if _, ok := f.perms(t, "carol")["team"]; ok {
		t.Error("carol still lists the channel she left")
	}
}

func TestEscalationIsBounded(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "club")
	for name, perms := range map[string]chatutil.Perms{"carol": chatutil.PresetModerator, "dave": chatutil.PresetModerator} {
		if err := f.set(t, "bob", channel.ID, f.users[name], 0, perms); err != nil {
			t.Fatal(err)
		}
	}
	extra := f.group(t, "extra")

	// A moderator may grant only what they hold.
	if err := f.set(t, "carol", channel.ID, 0, extra, chatutil.PresetOwner); !errors.Is(err, chatutil.ErrNotHeld) {
		t.Errorf("granting manage_channel without it = %v, want ErrNotHeld", err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["carol"], 0, chatutil.PermsAll); !errors.Is(err, chatutil.ErrNotHeld) {
		t.Errorf("granting herself manage_channel = %v, want ErrNotHeld", err)
	}
	if err := f.set(t, "carol", channel.ID, 0, extra, chatutil.PresetMember); err != nil {
		t.Errorf("granting what she holds = %v", err)
	}
	// ...and may remove or demote a strict subset of herself, and no one else.
	if err := f.set(t, "carol", channel.ID, 0, extra, chatutil.PresetViewer); err != nil {
		t.Errorf("demoting a smaller row = %v", err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["dave"], 0, chatutil.PresetMember); !errors.Is(err, chatutil.ErrNotSubset) {
		t.Errorf("demoting an equal = %v, want ErrNotSubset", err)
	}
	if err := f.remove("carol", channel.ID, f.users["dave"], 0); !errors.Is(err, chatutil.ErrNotSubset) {
		t.Errorf("removing an equal = %v, want ErrNotSubset", err)
	}
	if err := f.remove("carol", channel.ID, f.users["bob"], 0); !errors.Is(err, chatutil.ErrCreatorRow) {
		t.Errorf("removing the creator = %v, want ErrCreatorRow", err)
	}
	// Adding to someone's row is not a demotion.
	if err := f.set(t, "carol", channel.ID, f.users["dave"], 0, chatutil.PresetModerator); err != nil {
		t.Errorf("re-setting an equal's row unchanged = %v", err)
	}

	// A manage_channel holder is exempt from the subset rule, not from the
	// creator's row.
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PermsAll); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["dave"], 0, chatutil.PresetViewer); err != nil {
		t.Errorf("co-owner demoting a moderator = %v", err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["bob"], 0, chatutil.PresetModerator); !errors.Is(err, chatutil.ErrCreatorRow) {
		t.Errorf("co-owner demoting the creator = %v, want ErrCreatorRow", err)
	}
	if err := f.remove("carol", channel.ID, f.users["bob"], 0); !errors.Is(err, chatutil.ErrCreatorRow) {
		t.Errorf("co-owner removing the creator = %v, want ErrCreatorRow", err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetModerator); err != nil {
		t.Errorf("the creator demoting a co-owner = %v", err)
	}

	// An admin is exempt from all of it.
	if err := f.set(t, "admin", channel.ID, f.users["bob"], 0, chatutil.PresetViewer); err != nil {
		t.Errorf("admin demoting the creator = %v", err)
	}
	if err := f.remove("admin", channel.ID, f.users["bob"], 0); err != nil {
		t.Errorf("admin removing the creator = %v", err)
	}
}

func TestSetMemberRefusesIncoherentSets(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "sets")
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PermSendMessages); !errors.Is(err, chatutil.ErrInvalidPerms) {
		t.Errorf("send_messages alone = %v, want ErrInvalidPerms", err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, 0); !errors.Is(err, chatutil.ErrNoPerms) {
		t.Errorf("the empty set = %v, want ErrNoPerms", err)
	}
	// A delegated manager holds a management permission alone.
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PermManageMembers); err != nil {
		t.Errorf("manage_members alone = %v", err)
	}
	if got := f.perms(t, "carol")["sets"]; got != chatutil.PermManageMembers {
		t.Errorf("the delegated manager sees %v", got)
	}
	members, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: context.Background(), Database: f.database, Principal: f.as("carol"), ChannelID: channel.ID})
	if err != nil || len(members.Members) != 2 {
		t.Errorf("the delegated manager's ListMembers = %+v, %v", members, err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["dave"], 0, chatutil.PermManageMembers); err != nil {
		t.Errorf("the delegated manager adding a peer = %v", err)
	}
	if err := f.set(t, "carol", channel.ID, f.users["dave"], 0, chatutil.PresetViewer); !errors.Is(err, chatutil.ErrNotHeld) {
		t.Errorf("the delegated manager granting read_messages = %v, want ErrNotHeld", err)
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
	if err := f.set(t, "admin", general.ID, 0, f.everyone, chatutil.PermManageMembers); !errors.Is(err, chatutil.ErrDefaultEveryone) {
		t.Errorf("dropping everyone below Viewer on general = %v, want ErrDefaultEveryone", err)
	}
	if err := f.set(t, "admin", general.ID, 0, f.everyone, chatutil.PresetViewer); err != nil {
		t.Errorf("everyone at Viewer on general = %v", err)
	}
	if got := f.perms(t, "carol"); got["general"] != chatutil.PresetViewer {
		t.Errorf("carol sees %v after the refusals", got)
	}
}

func TestAdminManagesWithoutSeeing(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "private")
	if _, ok := f.perms(t, "admin")["private"]; ok {
		t.Error("admin lists a channel they aren't in")
	}

	name := "renamed"
	updated, err := chatutil.UpdateChannel(chatutil.UpdateChannelParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as("admin"), ChannelID: channel.ID, Name: &name,
	})
	if err != nil || updated.Channel.Name != "renamed" || updated.Channel.Permissions != 0 || !updated.Channel.IsPrivate {
		t.Errorf("admin rename = %+v, %v", updated.Channel, err)
	}
	members, err := chatutil.ListMembers(chatutil.ListMembersParams{Ctx: context.Background(), Database: f.database, Principal: f.as("admin"), ChannelID: channel.ID})
	if err != nil || len(members.Members) != 1 || members.Members[0].UserID != f.users["bob"] || members.Members[0].Permissions != chatutil.PermsAll {
		t.Errorf("admin ListMembers = %+v, %v", members, err)
	}
	if err := f.set(t, "admin", channel.ID, f.users["carol"], 0, chatutil.PresetViewer); err != nil {
		t.Errorf("admin SetMember = %v", err)
	}
	if _, ok := f.perms(t, "admin")["renamed"]; ok {
		t.Error("managing a channel made admin a member")
	}
	if _, err := chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: context.Background(), Database: f.database, Principal: f.as("admin"), ChannelID: channel.ID}); err != nil {
		t.Errorf("admin DeleteChannel = %v", err)
	}
	if _, ok := f.perms(t, "bob")["renamed"]; ok {
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
	if err := f.set(t, "bob", channel.ID, 999, 0, chatutil.PresetViewer); !errors.Is(err, accessutil.ErrPrincipalNotFound) {
		t.Errorf("SetMember of a missing account = %v", err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], f.everyone, chatutil.PresetViewer); !errors.Is(err, accessutil.ErrGrantTarget) {
		t.Errorf("SetMember of both kinds = %v", err)
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
	if err := f.set(t, "bob", channel.ID, 0, design, chatutil.PresetViewer); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}

	result, err := chatutil.ListMembers(chatutil.ListMembersParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("dave"), ChannelID: channel.ID, DataDir: dataDir,
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []chatutil.Member{
		{GroupID: design, Name: "design", Permissions: chatutil.PresetViewer, Users: []chatutil.MemberUser{
			{ID: f.users["carol"], Username: "carol", AvatarUpdatedAt: stamp.UnixMilli()},
			{ID: f.users["dave"], Username: "dave"},
		}},
		{UserID: f.users["bob"], Name: "bob", Permissions: chatutil.PermsAll},
		{UserID: f.users["carol"], Name: "carol", Permissions: chatutil.PresetMember, AvatarUpdatedAt: stamp.UnixMilli()},
	}
	if len(result.Members) != len(want) {
		t.Fatalf("ListMembers = %+v, want %+v", result.Members, want)
	}
	for i := range want {
		got := result.Members[i]
		if got.UserID != want[i].UserID || got.GroupID != want[i].GroupID || got.Name != want[i].Name ||
			got.Permissions != want[i].Permissions || got.AvatarUpdatedAt != want[i].AvatarUpdatedAt || !slices.Equal(got.Users, want[i].Users) {
			t.Errorf("member %d = %+v, want %+v", i, got, want[i])
		}
	}
	body, err := json.Marshal(result.Members[1])
	if err != nil || !strings.Contains(string(body), `"permissions":["read_messages","send_messages","add_reactions","delete_messages","manage_channel","manage_members","manage_reactions"]`) {
		t.Errorf("a member as JSON = %s, %v", body, err)
	}
}

func TestChangesTellMembersBeforeAndAfter(t *testing.T) {
	f := newFixture(t)
	events, unsub := f.bus.Subscribe("chat-test")
	defer unsub()
	next := func() eventbus.Event {
		t.Helper()
		select {
		case evt := <-events:
			if _, ok := evt.Data.(eventbus.ChatChannelChanged); evt.Kind != eventbus.EventChatChannelChanged || !ok {
				t.Fatalf("event = %+v", evt)
			}
			return evt
		default:
			t.Fatal("no chat_channel_changed event")
			return eventbus.Event{}
		}
	}
	has := func(evt eventbus.Event, names ...string) {
		t.Helper()
		changed := evt.Data.(eventbus.ChatChannelChanged)
		for _, name := range names {
			if !slices.Contains(changed.Audience, f.users[name]) {
				t.Errorf("audience %v is missing %s", changed.Audience, name)
			}
		}
		if slices.Contains(changed.Audience, f.users["dave"]) {
			t.Errorf("audience %v holds dave, who was never a member", changed.Audience)
		}
	}
	// deliver runs the event through the socket's filter as an account sees it.
	deliver := func(evt eventbus.Event, name string) bool {
		t.Helper()
		access, err := accessutil.Load(accessutil.LoadParams{Ctx: context.Background(), Database: f.database, Principal: f.as(name)})
		if err != nil {
			t.Fatal(err)
		}
		return accessutil.FilterEvent(accessutil.FilterEventParams{Access: access.Access, Event: evt}).Deliver
	}

	channel := f.create(t, "bob", "news")
	has(next(), "bob")
	// carol manages the channel without reading it: her set is not empty, so
	// she hears about it. dave's is empty, so he never does.
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PermManageMembers); err != nil {
		t.Fatal(err)
	}
	evt := next()
	has(evt, "bob", "carol")
	if !deliver(evt, "carol") || deliver(evt, "dave") {
		t.Errorf("delivered to the delegated manager %v, to dave %v; want true, false", deliver(evt, "carol"), deliver(evt, "dave"))
	}
	if err := f.remove("bob", channel.ID, f.users["carol"], 0); err != nil {
		t.Fatal(err)
	}
	has(next(), "bob", "carol")
	if _, err := chatutil.DeleteChannel(chatutil.DeleteChannelParams{Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as("bob"), ChannelID: channel.ID}); err != nil {
		t.Fatal(err)
	}
	evt = next()
	if changed := evt.Data.(eventbus.ChatChannelChanged); changed.ChannelID != channel.ID {
		t.Errorf("delete event = %+v", changed)
	}
	has(evt, "bob")
}

func TestLastManagerCannotLeaveOrBeDemotedExceptByAnAdmin(t *testing.T) {
	f := newFixture(t)
	channel := f.create(t, "bob", "design")
	if err := f.set(t, "bob", channel.ID, f.users["carol"], 0, chatutil.PresetMember); err != nil {
		t.Fatal(err)
	}

	if err := f.remove("bob", channel.ID, f.users["bob"], 0); !errors.Is(err, chatutil.ErrLastOwner) {
		t.Errorf("last manager leaving = %v, want ErrLastOwner", err)
	}
	if err := f.set(t, "bob", channel.ID, f.users["bob"], 0, chatutil.PresetModerator); !errors.Is(err, chatutil.ErrLastOwner) {
		t.Errorf("last manager dropping manage_channel = %v, want ErrLastOwner", err)
	}
	if got := f.perms(t, "bob")["design"]; got != chatutil.PermsAll {
		t.Errorf("after refusals bob holds %v, want everything: the change must roll back", got)
	}

	// A second holder, even through a group, lets the first one go.
	crew := f.group(t, "crew", "carol")
	if err := f.set(t, "bob", channel.ID, 0, crew, chatutil.PresetOwner); err != nil {
		t.Fatal(err)
	}
	if err := f.remove("bob", channel.ID, f.users["bob"], 0); err != nil {
		t.Errorf("leaving with another holder = %v", err)
	}
	if err := f.remove("carol", channel.ID, 0, crew); !errors.Is(err, chatutil.ErrLastOwner) {
		t.Errorf("removing the group holding the last manager = %v, want ErrLastOwner", err)
	}

	// An admin may leave a channel with no one to manage it.
	if err := f.remove("admin", channel.ID, 0, crew); err != nil {
		t.Errorf("admin removing the last manager = %v", err)
	}
	// With no holder left, a member may still leave.
	if err := f.remove("carol", channel.ID, f.users["carol"], 0); err != nil {
		t.Errorf("member leaving an unmanaged channel = %v", err)
	}

	// Alone in a channel, its last manager may leave it empty.
	solo := f.create(t, "bob", "solo")
	if err := f.remove("bob", solo.ID, f.users["bob"], 0); err != nil {
		t.Errorf("the only member leaving = %v", err)
	}
}

func TestListingEveryChannelIsForAdmins(t *testing.T) {
	f := newFixture(t)
	f.create(t, "bob", "secret")
	ctx := context.Background()

	if _, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: ctx, Database: f.database, Principal: f.as("bob"), All: true}); !errors.Is(err, chatutil.ErrAdminOnly) {
		t.Errorf("All for bob = %v, want ErrAdminOnly", err)
	}
	if got := f.perms(t, "admin"); len(got) != 1 || got["general"] != chatutil.PresetMember {
		t.Errorf("admin's own channels = %v, want only general", got)
	}
	result, err := chatutil.ListChannels(chatutil.ListChannelsParams{Ctx: ctx, Database: f.database, Principal: f.as("admin"), All: true})
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	var perms []chatutil.Perms
	for _, c := range result.Channels {
		names, perms = append(names, c.Name), append(perms, c.Permissions)
	}
	if !slices.Equal(names, []string{"general", "secret"}) || !slices.Equal(perms, []chatutil.Perms{chatutil.PresetMember, 0}) {
		t.Errorf("All for admin = %v %v, want general then secret with an empty set", names, perms)
	}
	if !result.Channels[1].IsPrivate {
		t.Errorf("secret = %+v, want private", result.Channels[1])
	}
}
