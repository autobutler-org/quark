package v0_chat_test

import (
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/autobutler-org/quark/pkg/util/chatutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

func TestAttachment_PutGetAndDelete(t *testing.T) {
	h := newHarness(t)
	dataDir := storageutil.GetDataDir()
	t.Cleanup(func() { _ = os.RemoveAll(filepath.Join(dataDir, "chat-attachments")) })

	var listed chatutil.ListChannelsResult
	h.expect(t, http.StatusOK, http.MethodGet, "/chat/channels", "bob", "", &listed)
	if len(listed.Channels) == 0 || listed.Channels[0].Name != "general" {
		t.Fatalf("channels = %+v", listed.Channels)
	}
	general := listed.Channels[0]
	id := strings.Repeat("0", 64)
	generalPath := "/chat/channels/" + strconv.FormatInt(general.ID, 10) + "/attachments/" + id

	var room chatutil.Channel
	h.expect(t, http.StatusCreated, http.MethodPost, "/chat/channels", "bob", `{"name":"files"}`, &room)
	roomPath := "/chat/channels/" + strconv.FormatInt(room.ID, 10)
	h.expect(t, http.StatusOK, http.MethodPut, roomPath+"/members", "bob", userBody(h.users["carol"], viewer...), nil)
	// A custom set without attach_files is still a valid set. It just cannot upload.
	h.expect(t, http.StatusOK, http.MethodPut, roomPath+"/members", "bob", userBody(h.users["dave"], "read_messages", "send_messages"), nil)
	h.expect(t, http.StatusForbidden, http.MethodPut, roomPath+"/attachments/"+id, "carol", "hello", nil)
	h.expect(t, http.StatusForbidden, http.MethodPut, roomPath+"/attachments/"+id, "dave", "hello", nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, roomPath+"/attachments/not-an-id", "bob", "hello", nil)
	h.expect(t, http.StatusBadRequest, http.MethodPut, roomPath+"/attachments/"+strings.Repeat("g", 64), "bob", "hello", nil)
	h.expect(t, http.StatusBadRequest, http.MethodGet, roomPath+"/attachments/"+strings.Repeat(".", 64), "bob", "", nil)

	h.drain()
	var put chatutil.PutAttachmentResult
	h.expect(t, http.StatusCreated, http.MethodPut, generalPath, "bob", "hello", &put)
	if put.ID != id || put.ByteSize != 5 {
		t.Fatalf("put = %+v", put)
	}
	if got := h.drain(); len(got) != 0 {
		t.Errorf("upload published %d events, want none", len(got))
	}
	h.expect(t, http.StatusNotFound, http.MethodGet, generalPath, "carol", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, "/chat/channels/"+strconv.FormatInt(general.ID, 10)+"/attachments/"+strings.Repeat("ab", 32), "bob", "", nil)
	h.expect(t, http.StatusNotFound, http.MethodGet, roomPath+"/attachments/"+id, "bob", "", nil)

	code, body := h.do(t, http.MethodGet, generalPath, "bob", "")
	if code != http.StatusOK || body != "hello" {
		t.Fatalf("get = %d %q, want 200 hello", code, body)
	}
	req, err := http.NewRequest(http.MethodGet, h.srv.URL+"/api/v0"+generalPath+"?as=bob", nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Range", "bytes=1-2")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	ranged, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusPartialContent || string(ranged) != "el" || len(ranged) != 2 {
		t.Fatalf("range = %d %q, want 206 el", resp.StatusCode, ranged)
	}
	if got := resp.Header.Get("Content-Type"); got != "application/octet-stream" {
		t.Errorf("Content-Type = %q", got)
	}
	if got := resp.Header.Get("Accept-Ranges"); got != "bytes" {
		t.Errorf("Accept-Ranges = %q", got)
	}
	if got := resp.Header.Get("Cache-Control"); got != "private, no-store" {
		t.Errorf("Cache-Control = %q", got)
	}
	h.expect(t, http.StatusConflict, http.MethodPut, generalPath, "bob", "again", nil)

	other := strings.Repeat("a", 64)
	h.expect(t, http.StatusCreated, http.MethodPut, roomPath+"/attachments/"+other, "bob", "world", nil)
	file, err := chatutil.AttachmentPath(dataDir, room.ID, other)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(file); err != nil {
		t.Fatalf("attachment file: %v", err)
	}
	h.expect(t, http.StatusNoContent, http.MethodDelete, roomPath, "bob", "", nil)
	if _, err := os.Stat(file); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("file after channel delete: %v", err)
	}
}
