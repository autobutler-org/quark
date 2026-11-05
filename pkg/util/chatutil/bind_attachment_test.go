package chatutil_test

import (
	"context"
	"database/sql"
	"errors"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

func (f fixture) putAttachment(t *testing.T, as string, channelID int64, id, dir, body string) {
	t.Helper()
	_, err := chatutil.PutAttachment(chatutil.PutAttachmentParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as(as),
		ChannelID: channelID, ID: id, DataDir: dir, Body: strings.NewReader(body),
	})
	if err != nil {
		t.Fatalf("put attachment %s: %v", id, err)
	}
}

func (f fixture) messageCount(t *testing.T, channelID int64) int {
	t.Helper()
	page, err := chatutil.ListMessages(chatutil.ListMessagesParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), ChannelID: channelID,
	})
	if err != nil {
		t.Fatal(err)
	}
	return len(page.Messages)
}

func (f fixture) openAttachment(t *testing.T, as string, channelID int64, id, dir string) string {
	t.Helper()
	opened, err := chatutil.OpenAttachment(chatutil.OpenAttachmentParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as(as),
		ChannelID: channelID, ID: id, DataDir: dir,
	})
	if err != nil {
		t.Fatalf("open attachment as %s: %v", as, err)
	}
	defer opened.File.Close()
	body, err := io.ReadAll(opened.File)
	if err != nil {
		t.Fatal(err)
	}
	return string(body)
}

func (f fixture) postAttachments(as string, channelID int64, ciphertext []byte, clientMessageID string, ids []string) (chatutil.PostMessageResult, error) {
	return chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		ChannelID: channelID, KeyVersion: 1, Ciphertext: ciphertext, ClientMessageID: clientMessageID,
		AttachmentIDs: ids,
	})
}

// TestPostMessageBindsAttachments binds uploaded files to a message, keeps a
// retry of that message from failing, and removes the files when the message
// is deleted.
func TestPostMessageBindsAttachments(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	dir := t.TempDir()
	id := strings.Repeat("ab", 32)
	other := strings.Repeat("cd", 32)
	f.putAttachment(t, "bob", room, id, dir, "hello")
	f.putAttachment(t, "bob", room, other, dir, "world")

	if _, err := chatutil.OpenAttachment(chatutil.OpenAttachmentParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("carol"),
		ChannelID: room, ID: id, DataDir: dir,
	}); !errors.Is(err, chatutil.ErrAttachmentNotFound) {
		t.Fatalf("unbound open as carol: %v, want ErrAttachmentNotFound", err)
	}

	posted, err := f.postAttachments("bob", room, sealedMessage('n', 'a'), "send-1", []string{id})
	if err != nil || posted.Repeated {
		t.Fatalf("post = %+v, %v", posted, err)
	}
	if got := f.openAttachment(t, "carol", room, id, dir); got != "hello" {
		t.Fatalf("bound open = %q, want hello", got)
	}

	again, err := f.postAttachments("bob", room, sealedMessage('n', 'a'), "", []string{id})
	if err != nil || !again.Repeated || again.Message.ID != posted.Message.ID {
		t.Fatalf("identical retry = %+v, %v; want message %d", again, err, posted.Message.ID)
	}
	fresh, err := f.postAttachments("bob", room, sealedMessage('m', 'b'), "send-1", []string{id})
	if err != nil || !fresh.Repeated || fresh.Message.ID != posted.Message.ID {
		t.Fatalf("client id retry = %+v, %v; want message %d", fresh, err, posted.Message.ID)
	}

	before := f.messageCount(t, room)
	if _, err := f.postAttachments("bob", room, sealedMessage('q', 'c'), "send-2", []string{id}); !errors.Is(err, chatutil.ErrAttachmentNotFound) {
		t.Fatalf("id bound to another message: %v, want ErrAttachmentNotFound", err)
	}
	if _, err := f.postAttachments("bob", room, sealedMessage('r', 'd'), "", []string{strings.Repeat("ef", 32)}); !errors.Is(err, chatutil.ErrAttachmentNotFound) {
		t.Fatalf("unknown id: %v, want ErrAttachmentNotFound", err)
	}
	many := make([]string, chatutil.MaxAttachmentsPerMessage+1)
	for i := range many {
		many[i] = strings.Repeat(string("0123456789abcdef"[i]), 64)
	}
	if _, err := f.postAttachments("bob", room, sealedMessage('s', 'e'), "", many); !errors.Is(err, chatutil.ErrTooManyAttachments) {
		t.Fatalf("11 ids: %v, want ErrTooManyAttachments", err)
	}
	if _, err := f.postAttachments("bob", room, sealedMessage('t', 'f'), "", []string{"nope"}); !errors.Is(err, chatutil.ErrInvalidAttachment) {
		t.Fatalf("bad id: %v, want ErrInvalidAttachment", err)
	}
	if got := f.messageCount(t, room); got != before {
		t.Fatalf("failed posts stored messages: %d, was %d", got, before)
	}

	if _, err := f.postAttachments("bob", room, sealedMessage('o', 'a'), "send-3", []string{other}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.postAttachments("bob", room, sealedMessage('p', 'b'), "send-3", []string{id}); !errors.Is(err, chatutil.ErrAttachmentNotFound) {
		t.Fatalf("retry naming another message's attachment: %v, want ErrAttachmentNotFound", err)
	}

	path, err := chatutil.AttachmentPath(dir, room, id)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("attachment file: %v", err)
	}
	if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), MessageID: posted.Message.ID, DataDir: dir,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("file after delete: %v", err)
	}
	if _, err := f.database.Queries.GetChatAttachment(context.Background(), id); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("attachment row after delete: %v, want ErrNoRows", err)
	}
	deleted, err := f.postAttachments("bob", room, sealedMessage('u', 'z'), "send-1", []string{id})
	if err != nil || !deleted.Repeated || deleted.Message.ID != posted.Message.ID || deleted.Message.DeletedAt == nil {
		t.Fatalf("retry of deleted message = %+v, %v; want tombstone %d", deleted, err, posted.Message.ID)
	}

	kept := strings.Repeat("12", 32)
	f.putAttachment(t, "bob", room, kept, dir, "stay")
	keptMsg, err := f.postAttachments("bob", room, sealedMessage('k', 'a'), "", []string{kept})
	if err != nil {
		t.Fatal(err)
	}
	keptPath, err := chatutil.AttachmentPath(dir, room, kept)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), MessageID: keptMsg.Message.ID,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(keptPath); err != nil {
		t.Fatalf("empty DataDir removed the file: %v", err)
	}
	if _, err := f.database.Queries.GetChatAttachment(context.Background(), kept); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("row after delete without DataDir: %v, want ErrNoRows", err)
	}

	if err := f.set(t, "bob", room, f.users["carol"], 0, chatutil.PermReadMessages|chatutil.PermSendMessages|chatutil.PermAttachFiles); err != nil {
		t.Fatal(err)
	}
	carolID := strings.Repeat("34", 32)
	f.putAttachment(t, "carol", room, carolID, dir, "nope")
	if _, err := f.postAttachments("bob", room, sealedMessage('v', 'a'), "", []string{carolID}); !errors.Is(err, chatutil.ErrAttachmentNotFound) {
		t.Fatalf("someone else's upload: %v, want ErrAttachmentNotFound", err)
	}
	aside := f.keyedRoom(t, "aside")
	asideID := strings.Repeat("56", 32)
	f.putAttachment(t, "bob", aside, asideID, dir, "elsewhere")
	if _, err := f.postAttachments("bob", room, sealedMessage('w', 'b'), "", []string{asideID}); !errors.Is(err, chatutil.ErrAttachmentNotFound) {
		t.Fatalf("another channel's upload: %v, want ErrAttachmentNotFound", err)
	}
	if got := f.messageCount(t, room); got != before+2 {
		t.Fatalf("messages = %d, want %d", got, before+2)
	}
}
