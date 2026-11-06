package chatutil_test

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
)

func TestAttachmentSweepRemovesExpiredUnboundFiles(t *testing.T) {
	f := newFixture(t)
	dir := t.TempDir()
	channel := f.create(t, "bob", "drops")
	ctx := context.Background()
	stale := strings.Repeat("1", 64)
	fresh := strings.Repeat("2", 64)
	put := func(id, body string) {
		t.Helper()
		result, err := chatutil.PutAttachment(chatutil.PutAttachmentParams{
			Ctx: ctx, Database: f.database, Principal: f.as("bob"),
			ChannelID: channel.ID, ID: id, DataDir: dir, Body: strings.NewReader(body),
		})
		if err != nil || result.ByteSize != int64(len(body)) {
			t.Fatalf("PutAttachment(%s) = %+v, %v", id, result, err)
		}
	}
	put(stale, "old")
	if _, err := f.database.Db.ExecContext(ctx, `UPDATE chat_attachments SET created_at = ? WHERE id = ?`, time.Now().Add(-25*time.Hour), stale); err != nil {
		t.Fatal(err)
	}
	put(fresh, "new")

	stalePath, err := chatutil.AttachmentPath(dir, channel.ID, stale)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(stalePath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("expired file = %v, want it removed", err)
	}
	if _, err := f.database.Queries.GetChatAttachment(ctx, stale); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("expired row = %v, want it removed", err)
	}
	freshPath, err := chatutil.AttachmentPath(dir, channel.ID, fresh)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(freshPath); err != nil {
		t.Fatalf("fresh file: %v", err)
	}
}
