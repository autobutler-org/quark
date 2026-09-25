package chatutil_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/authutil"
	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

// sampleKeys is a well-formed identity whose bytes are filled with fill, so
// two accounts' keys are told apart.
func sampleKeys(fill byte) chatutil.Keys {
	b := func(n int) []byte { return bytes.Repeat([]byte{fill}, n) }
	return chatutil.Keys{
		BoxPublicKey:      b(chatutil.PublicKeyBytes),
		SignPublicKey:     b(chatutil.PublicKeyBytes),
		WrappedByPassword: b(104),
		SaltPw:            b(chatutil.SaltBytes),
		WrappedByPhrase:   b(104),
		SaltRp:            b(chatutil.SaltBytes),
		KdfParams:         json.RawMessage(`{"alg":"argon2id13","opsLimit":3,"memLimit":67108864}`),
	}
}

func TestValidateKeys(t *testing.T) {
	cases := map[string]func(*chatutil.Keys){
		"short box key":          func(k *chatutil.Keys) { k.BoxPublicKey = k.BoxPublicKey[:31] },
		"long sign key":          func(k *chatutil.Keys) { k.SignPublicKey = append(k.SignPublicKey, 0) },
		"no password wrap":       func(k *chatutil.Keys) { k.WrappedByPassword = nil },
		"oversized wrap":         func(k *chatutil.Keys) { k.WrappedByPassword = make([]byte, chatutil.MaxWrappedKeyBytes+1) },
		"short salt":             func(k *chatutil.Keys) { k.SaltPw = k.SaltPw[:8] },
		"phrase wrap, no salt":   func(k *chatutil.Keys) { k.SaltRp = nil },
		"phrase salt, no wrap":   func(k *chatutil.Keys) { k.WrappedByPhrase = nil },
		"kdf params not object":  func(k *chatutil.Keys) { k.KdfParams = json.RawMessage(`[1]`) },
		"kdf params missing":     func(k *chatutil.Keys) { k.KdfParams = nil },
		"kdf params too long":    func(k *chatutil.Keys) { k.KdfParams = json.RawMessage(`{"a":"` + string(make([]byte, 600)) + `"}`) },
		"kdf params not json":    func(k *chatutil.Keys) { k.KdfParams = json.RawMessage(`{`) },
		"empty phrase wrap pair": func(k *chatutil.Keys) { k.WrappedByPhrase, k.SaltRp = []byte{}, []byte{} },
	}
	for name, mutate := range cases {
		keys := sampleKeys(1)
		mutate(&keys)
		if err := chatutil.ValidateKeys(keys); !errors.Is(err, chatutil.ErrInvalidKeys) {
			t.Errorf("%s: ValidateKeys = %v, want ErrInvalidKeys", name, err)
		}
	}
	if err := chatutil.ValidateKeys(sampleKeys(1)); err != nil {
		t.Errorf("well-formed keys: %v", err)
	}
	noPhrase := sampleKeys(1)
	noPhrase.WrappedByPhrase, noPhrase.SaltRp = nil, nil
	if err := chatutil.ValidateKeys(noPhrase); err != nil {
		t.Errorf("keys without a phrase wrap: %v", err)
	}
}

func TestPutAndGetKeys(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	q := f.database.Queries

	if _, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"]}); !errors.Is(err, chatutil.ErrKeysNotFound) {
		t.Fatalf("GetKeys before any = %v, want ErrKeysNotFound", err)
	}
	put, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"], Keys: sampleKeys(1)})
	if err != nil {
		t.Fatal(err)
	}
	// Without a phrase wrap, which a key made at a later sign-in lacks.
	replacement := sampleKeys(2)
	replacement.WrappedByPhrase, replacement.SaltRp = nil, nil
	if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"], Keys: replacement}); err != nil {
		t.Fatal(err)
	}
	got, err := chatutil.GetKeys(chatutil.GetKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"]})
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got.Keys.BoxPublicKey, replacement.BoxPublicKey) || got.Keys.WrappedByPhrase != nil || got.Keys.SaltRp != nil {
		t.Errorf("GetKeys after replace = %+v, want the replacement with no phrase wrap", got.Keys)
	}
	if !got.Keys.CreatedAt.Equal(put.Keys.CreatedAt) {
		t.Errorf("replace moved created_at from %v to %v", put.Keys.CreatedAt, got.Keys.CreatedAt)
	}
	if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"], Keys: chatutil.Keys{}}); !errors.Is(err, chatutil.ErrInvalidKeys) {
		t.Errorf("PutKeys of empty keys = %v, want ErrInvalidKeys", err)
	}
}

// TestGetPublicKeys_OnlyPublicHalf checks another account sees the public
// keys and nothing wrapped, and nothing at all for an inactive account.
func TestGetPublicKeys_OnlyPublicHalf(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	q := f.database.Queries
	if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"], Keys: sampleKeys(3)}); err != nil {
		t.Fatal(err)
	}

	got, err := chatutil.GetPublicKeys(chatutil.GetPublicKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"]})
	if err != nil {
		t.Fatal(err)
	}
	encoded, _ := json.Marshal(got.PublicKeys)
	var fields map[string]any
	_ = json.Unmarshal(encoded, &fields)
	if len(fields) != 3 || fields["boxPublicKey"] == nil || fields["signPublicKey"] == nil || fields["userId"] == nil {
		t.Errorf("public keys = %s, want only userId, boxPublicKey and signPublicKey", encoded)
	}

	if _, err := chatutil.GetPublicKeys(chatutil.GetPublicKeysParams{Ctx: ctx, Queries: q, UserID: f.users["carol"]}); !errors.Is(err, chatutil.ErrKeysNotFound) {
		t.Errorf("carol without keys = %v, want ErrKeysNotFound", err)
	}
	if n, err := q.SetUserStatus(ctx, db.SetUserStatusParams{Username: "bob", FromStatus: authutil.StatusActive, ToStatus: authutil.StatusDisabled}); err != nil || n != 1 {
		t.Fatalf("disable bob: rows=%d err=%v", n, err)
	}
	if _, err := chatutil.GetPublicKeys(chatutil.GetPublicKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"]}); !errors.Is(err, chatutil.ErrKeysNotFound) {
		t.Errorf("disabled bob = %v, want ErrKeysNotFound", err)
	}
}

// TestDeleteUser_RemovesChatKeys checks a deleted account's chat identity
// goes with it, whichever deletion path ran: the admin's and the account's
// own both go through authutil.DeleteUser.
func TestDeleteUser_RemovesChatKeys(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	q := f.database.Queries
	if _, err := chatutil.PutKeys(chatutil.PutKeysParams{Ctx: ctx, Queries: q, UserID: f.users["bob"], Keys: sampleKeys(4)}); err != nil {
		t.Fatal(err)
	}
	if _, err := authutil.DeleteUser(ctx, authutil.DeleteUserParams{Database: f.database, ActorUserID: f.users["admin"], Username: "bob"}); err != nil {
		t.Fatal(err)
	}
	var n int
	if err := f.database.Db.QueryRow(`SELECT COUNT(*) FROM user_chat_keys WHERE user_id = ?`, f.users["bob"]).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Errorf("bob's chat keys survived his deletion: %d rows", n)
	}
}
