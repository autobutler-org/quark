package v0_chat_test

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func messageWithAttachments(fill byte, n int, ids []string) string {
	parts := make([]string, len(ids))
	for i, id := range ids {
		parts[i] = `"` + id + `"`
	}
	return `{"keyVersion":1,"ciphertext":"` + b64(fill, n) + `","attachmentIds":[` + strings.Join(parts, ",") + `]}`
}

// TestAttachment_BindAndDelete binds an uploaded file to a message, lets
// another reader fetch it, and removes the file when the message is deleted.
func TestAttachment_BindAndDelete(t *testing.T) {
	h := newHarness(t)
	dataDir := storageutil.GetDataDir()
	t.Cleanup(func() { _ = os.RemoveAll(filepath.Join(dataDir, "chat-attachments")) })

	roomID, room := roomWithKey(t, h)
	h.expect(t, http.StatusOK, http.MethodPut, room+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	id := strings.Repeat("c", 64)
	attachment := room + "/attachments/" + id
	h.expect(t, http.StatusCreated, http.MethodPut, attachment, "bob", "hello", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, attachment, "carol", "", nil)

	var posted chatutil.Message
	h.expect(t, http.StatusCreated, http.MethodPost, room+"/messages", "bob", messageWithAttachments('a', 40, []string{id}), &posted)
	code, got := h.do(t, http.MethodGet, attachment, "carol", "")
	if code != http.StatusOK || got != "hello" {
		t.Fatalf("bound get = %d %q, want 200 hello", code, got)
	}

	file, err := chatutil.AttachmentPath(dataDir, roomID, id)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(file); err != nil {
		t.Fatalf("attachment file: %v", err)
	}
	h.expect(t, http.StatusOK, http.MethodDelete, "/chat/messages/"+strconv.FormatInt(posted.ID, 10), "bob", "", nil)
	if _, err := os.Stat(file); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("file after message delete: %v", err)
	}

	var page chatutil.ListMessagesResult
	h.expect(t, http.StatusOK, http.MethodGet, room+"/messages", "bob", "", &page)
	before := ids(page)
	unknown := strings.Repeat("d", 64)
	code, got = h.do(t, http.MethodPost, room+"/messages", "bob", messageWithAttachments('b', 40, []string{unknown}))
	if code != http.StatusNotFound || !strings.Contains(got, "no attachment has that id") {
		t.Fatalf("unknown attachment = %d %s, want 404", code, got)
	}
	h.expect(t, http.StatusOK, http.MethodGet, room+"/messages", "bob", "", &page)
	if got := ids(page); len(got) != len(before) || got[0] != before[0] {
		t.Fatalf("messages after unknown attachment = %v, want %v", got, before)
	}

	many := make([]string, 11)
	for i := range many {
		many[i] = strings.Repeat(string("0123456789abcdef"[i]), 64)
	}
	code, got = h.do(t, http.MethodPost, room+"/messages", "bob", messageWithAttachments('e', 40, many))
	if code != http.StatusBadRequest || !strings.Contains(got, "at most 10") {
		t.Fatalf("11 attachments = %d %s, want 400", code, got)
	}
	h.expect(t, http.StatusOK, http.MethodGet, room+"/messages", "bob", "", &page)
	if got := ids(page); len(got) != len(before) {
		t.Fatalf("messages after 11 ids = %v, want %v", got, before)
	}
}
