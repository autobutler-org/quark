package chatutil_test

import (
	"bytes"
	"context"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

// TestAnonymousPollInDirectMessage holds a poll in a direct message to the
// same rules as in a named channel: rows name no account, one answer per
// account, and each sees only their own as mine (#3942).
func TestAnonymousPollInDirectMessage(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	dir := t.TempDir()
	f.publishKeys(t, "bob", "carol")
	room := f.dm(t, "bob", "carol").Channel.ID
	if _, err := f.createVersion("bob", room, 1); err != nil {
		t.Fatal(err)
	}
	posted, err := chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: room, KeyVersion: 1,
		Ciphertext: sealedMessage('n', 'p'), Poll: &chatutil.PollSettings{Anonymous: true}, DataDir: dir,
	})
	if err != nil {
		t.Fatal(err)
	}
	answer := func(as string) error {
		_, err := chatutil.AnswerPoll(chatutil.AnswerPollParams{
			Ctx: ctx, Database: f.database, Principal: f.as(as), MessageID: posted.Message.ID, KeyVersion: 1,
			Ciphertext: bytes.Repeat([]byte{as[0]}, chatutil.PollAnswerCiphertextBytes), DataDir: dir,
		})
		return err
	}
	for _, as := range []string{"bob", "carol"} {
		if err := answer(as); err != nil {
			t.Fatalf("%s answering: %v", as, err)
		}
	}
	if err := answer("carol"); !errors.Is(err, chatutil.ErrAlreadyAnswered) {
		t.Errorf("carol's second answer = %v, want ErrAlreadyAnswered", err)
	}
	var named int
	if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM chat_poll_answers WHERE message_id = ? AND user_id IS NOT NULL`,
		posted.Message.ID).Scan(&named); err != nil || named != 0 {
		t.Errorf("%d answers name an account (%v), want 0", named, err)
	}
	listed, err := chatutil.ListPollAnswers(chatutil.ListPollAnswersParams{
		Ctx: ctx, Database: f.database, Principal: f.as("carol"), MessageID: posted.Message.ID, DataDir: dir,
	})
	if err != nil {
		t.Fatal(err)
	}
	mine := 0
	for _, a := range listed.Answers {
		if a.UserID != 0 {
			t.Errorf("served answer names account %d", a.UserID)
		}
		if a.Mine {
			mine++
			if a.Ciphertext[0] != 'c' {
				t.Errorf("carol's mine is %q's answer", a.Ciphertext[0])
			}
		}
	}
	if len(listed.Answers) != 2 || mine != 1 {
		t.Errorf("carol sees %d answers, %d hers; want 2 and 1", len(listed.Answers), mine)
	}
}

// TestDeleteAnonymousPollAnswers removes a deleted account's anonymous answer,
// which no cascade can find because the row names no account (#3942), and
// leaves everyone else's.
func TestDeleteAnonymousPollAnswers(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	dir := t.TempDir()
	room := f.keyedRoom(t, "room")
	if err := f.set(t, "bob", room, f.users["carol"], 0, chatutil.PermReadMessages|chatutil.PermAddReactions); err != nil {
		t.Fatal(err)
	}
	posted, err := chatutil.PostMessage(chatutil.PostMessageParams{
		Ctx: ctx, Database: f.database, Principal: f.as("bob"), ChannelID: room, KeyVersion: 1,
		Ciphertext: sealedMessage('n', 'p'), Poll: &chatutil.PollSettings{Anonymous: true}, DataDir: dir,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, as := range []string{"bob", "carol"} {
		if _, err := chatutil.AnswerPoll(chatutil.AnswerPollParams{
			Ctx: ctx, Database: f.database, Principal: f.as(as), MessageID: posted.Message.ID, KeyVersion: 1,
			Ciphertext: bytes.Repeat([]byte{'a'}, chatutil.PollAnswerCiphertextBytes), DataDir: dir,
		}); err != nil {
			t.Fatalf("%s answering: %v", as, err)
		}
	}

	if err := chatutil.DeleteAnonymousPollAnswers(chatutil.DeleteAnonymousPollAnswersParams{
		Ctx: ctx, Queries: f.database.Queries, DataDir: dir, UserID: f.users["carol"],
	}); err != nil {
		t.Fatal(err)
	}
	listed, err := chatutil.ListPollAnswers(chatutil.ListPollAnswersParams{
		Ctx: ctx, Database: f.database, Principal: f.as("bob"), MessageID: posted.Message.ID, DataDir: dir,
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(listed.Answers) != 1 || !listed.Answers[0].Mine {
		t.Errorf("answers after deleting carol's = %+v, want only bob's own", listed.Answers)
	}
}
