package chatutil_test

import (
	"bytes"
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// keyedRoom is a channel bob created with key version 1, where carol reads
// and sends too.
func (f fixture) keyedRoom(t *testing.T, name string) int64 {
	t.Helper()
	f.publishKeys(t, "bob", "carol")
	room := f.create(t, "bob", name)
	if _, err := f.createVersion("bob", room.ID, 1); err != nil {
		t.Fatal(err)
	}
	if err := f.set(t, "bob", room.ID, f.users["carol"], 0, chatutil.PermReadMessages|chatutil.PermSendMessages); err != nil {
		t.Fatal(err)
	}
	return room.ID
}

func (f fixture) post(as string, channelID int64, ciphertext []byte) (chatutil.PostMessageResult, error) {
	return chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: context.Background(), Database: f.database, EventBus: f.bus, Principal: f.as(as),
		ChannelID: channelID, KeyVersion: 1, Ciphertext: ciphertext,
	})
}

// sealedMessage is ciphertext whose nonce is all nonce and whose body is all
// body.
func sealedMessage(nonce, body byte) []byte {
	return append(bytes.Repeat([]byte{nonce}, chatutil.NonceBytes), bytes.Repeat([]byte{body}, 32)...)
}

// TestPostMessageRefusesReplay checks a nonce is stored once per channel and
// key version (#2487): the author repeating the exact post gets the stored
// message back and nothing new is announced, and anyone else replaying it,
// the same nonce with another body, or a repeat of a deleted message is
// ErrDuplicateMessage.
func TestPostMessageRefusesReplay(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")
	events, unsubscribe := f.bus.Subscribe("replay-test")
	defer unsubscribe()

	first, err := f.post("bob", room, sealedMessage('n', 'a'))
	if err != nil || first.Repeated {
		t.Fatalf("first post = %+v, %v", first, err)
	}
	<-events

	again, err := f.post("bob", room, sealedMessage('n', 'a'))
	if err != nil || !again.Repeated || again.Message.ID != first.Message.ID {
		t.Fatalf("bob repeating his post = %+v, %v; want message %d back", again, err, first.Message.ID)
	}
	select {
	case evt := <-events:
		if evt.Kind == eventbus.EventChatMessageCreated {
			t.Errorf("a repeated post was announced: %+v", evt)
		}
	default:
	}

	for _, replay := range []struct {
		name       string
		as         string
		ciphertext []byte
	}{
		{"carol replaying bob's ciphertext", "carol", sealedMessage('n', 'a')},
		{"the same nonce with another body", "bob", sealedMessage('n', 'b')},
	} {
		if _, err := f.post(replay.as, room, replay.ciphertext); !errors.Is(err, chatutil.ErrDuplicateMessage) {
			t.Errorf("%s: %v, want ErrDuplicateMessage", replay.name, err)
		}
	}

	other := f.keyedRoom(t, "other")
	if _, err := f.post("bob", other, sealedMessage('n', 'a')); err != nil {
		t.Errorf("the same ciphertext in another channel: %v", err)
	}

	if _, err := chatutil.DeleteMessage(chatutil.DeleteMessageParams{
		Ctx: context.Background(), Database: f.database, Principal: f.as("bob"), MessageID: first.Message.ID,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.post("bob", room, sealedMessage('n', 'a')); !errors.Is(err, chatutil.ErrDuplicateMessage) {
		t.Errorf("posting a deleted message again: %v, want ErrDuplicateMessage", err)
	}
}

// TestPostMessageConcurrentReplay races the same ciphertext from both of a
// channel's senders and checks the unique index lets exactly one row in.
func TestPostMessageConcurrentReplay(t *testing.T) {
	f := newFixture(t)
	room := f.keyedRoom(t, "room")

	const racers = 16
	var wg sync.WaitGroup
	results := make([]chatutil.PostMessageResult, racers)
	errs := make([]error, racers)
	for i := range racers {
		wg.Go(func() {
			as := "bob"
			if i%2 == 1 {
				as = "carol"
			}
			results[i], errs[i] = f.post(as, room, sealedMessage('r', 'x'))
		})
	}
	wg.Wait()

	stored := map[int64]bool{}
	created := 0
	for i, err := range errs {
		switch {
		case err == nil:
			stored[results[i].Message.ID] = true
			if !results[i].Repeated {
				created++
			}
		case !errors.Is(err, chatutil.ErrDuplicateMessage):
			t.Errorf("racer %d: %v", i, err)
		}
	}
	if created != 1 || len(stored) != 1 {
		t.Errorf("created %d, stored ids %v; want one message", created, stored)
	}
	var rows int
	if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM chat_messages WHERE channel_id = ?`, room).Scan(&rows); err != nil {
		t.Fatal(err)
	}
	if rows != 1 {
		t.Errorf("rows = %d, want 1", rows)
	}
}
