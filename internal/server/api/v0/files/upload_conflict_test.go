package v0_files_test

import (
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/gin-gonic/gin"
)

// One collision rule on every upload path (#2016). A name that is taken is a
// 409 whether the file goes through the VFS or the StorageService, in one
// multipart request or in chunks, and it is never silently renamed. The client
// answers the 409 by asking again with keepBoth (the server picks a free name)
// or overwrite (the upload replaces the file).
func TestUploadNameConflict(t *testing.T) {
	t.Parallel()

	engines := []struct {
		name   string
		engine func(t *testing.T) (*gin.Engine, string)
	}{
		{name: "storage service", engine: newTestEngine},
		{name: "vfs", engine: newStorageVFSTestEngine},
	}
	cases := []struct {
		name  string
		query string
		code  int
		// want maps a name in notes/ to the content it must hold afterwards;
		// "" means the name must not exist.
		want map[string]string
	}{
		{
			name: "no choice is a conflict",
			code: http.StatusConflict,
			want: map[string]string{"clash.txt": "original", "clash_(1).txt": ""},
		},
		{
			name:  "keep both lands under a free name",
			query: "?keepBoth=true",
			code:  http.StatusOK,
			want:  map[string]string{"clash.txt": "original", "clash_(1).txt": "second"},
		},
		{
			name:  "overwrite replaces",
			query: "?overwrite=true",
			code:  http.StatusOK,
			want:  map[string]string{"clash.txt": "second", "clash_(1).txt": ""},
		},
		{
			name:  "both choices at once is refused",
			query: "?keepBoth=true&overwrite=true",
			code:  http.StatusBadRequest,
			want:  map[string]string{"clash.txt": "original", "clash_(1).txt": ""},
		},
	}

	for _, eng := range engines {
		for _, tc := range cases {
			t.Run(eng.name+"/"+tc.name, func(t *testing.T) {
				t.Parallel()
				e, filesDir := eng.engine(t)
				if w := uploadFile(t, e, "/api/v0/files/upload/notes", "clash.txt", "original"); w.Code != http.StatusOK {
					t.Fatalf("first upload returned %d: %s", w.Code, w.Body.String())
				}
				w := uploadFile(t, e, "/api/v0/files/upload/notes"+tc.query, "clash.txt", "second")
				if w.Code != tc.code {
					t.Fatalf("second upload returned %d, want %d: %s", w.Code, tc.code, w.Body.String())
				}
				assertContents(t, filepath.Join(filesDir, "notes"), tc.want)
			})
		}
	}
}

// An upload answers with where each file landed, keepBoth's rename included,
// so a client can act on the file it just sent (#2240).
func TestUploadReportsLandedPaths(t *testing.T) {
	t.Parallel()

	engines := []struct {
		name   string
		engine func(t *testing.T) (*gin.Engine, string)
	}{
		{name: "storage service", engine: newTestEngine},
		{name: "vfs", engine: newStorageVFSTestEngine},
	}
	for _, eng := range engines {
		t.Run(eng.name, func(t *testing.T) {
			t.Parallel()
			e, _ := eng.engine(t)
			for _, want := range []string{"notes/clash.txt", "notes/clash_(1).txt"} {
				w := uploadFile(t, e, "/api/v0/files/upload/notes?keepBoth=true", "clash.txt", "x")
				if w.Code != http.StatusOK {
					t.Fatalf("upload returned %d: %s", w.Code, w.Body.String())
				}
				var got struct {
					Paths []string `json:"paths"`
				}
				if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
					t.Fatalf("decode upload response: %v\nbody: %s", err, w.Body.String())
				}
				if len(got.Paths) != 1 || got.Paths[0] != want {
					t.Fatalf("paths = %v, want [%s]", got.Paths, want)
				}
			}
		})
	}
}

// The chunked path answers the clash when the session is opened, before a
// byte is staged, so a client never sends gigabytes only to be told the name
// is taken.
func TestUploadSessionNameConflict(t *testing.T) {
	t.Parallel()

	engines := []struct {
		name   string
		engine func(t *testing.T) (*gin.Engine, string)
	}{
		{name: "storage service", engine: newTestEngine},
		{name: "vfs", engine: newStorageVFSTestEngine},
	}
	for _, eng := range engines {
		t.Run(eng.name+"/opening on a taken name is a conflict", func(t *testing.T) {
			t.Parallel()
			e, filesDir := eng.engine(t)
			if w := uploadFile(t, e, "/api/v0/files/upload/notes", "clash.bin", "original"); w.Code != http.StatusOK {
				t.Fatalf("first upload returned %d: %s", w.Code, w.Body.String())
			}
			w := openSession(t, e, map[string]any{"rootDir": "notes", "fileName": "clash.bin", "totalSize": 4})
			if w.Code != http.StatusConflict {
				t.Fatalf("open session returned %d, want %d: %s", w.Code, http.StatusConflict, w.Body.String())
			}
			assertContents(t, filepath.Join(filesDir, "notes"), map[string]string{"clash.bin": "original"})
		})
		t.Run(eng.name+"/keep both commits under a free name", func(t *testing.T) {
			t.Parallel()
			e, filesDir := eng.engine(t)
			if w := uploadFile(t, e, "/api/v0/files/upload/notes", "clash.bin", "original"); w.Code != http.StatusOK {
				t.Fatalf("first upload returned %d: %s", w.Code, w.Body.String())
			}
			w := openSession(t, e, map[string]any{
				"rootDir": "notes", "fileName": "clash.bin", "totalSize": 4, "keepBoth": true,
			})
			if w.Code != http.StatusOK {
				t.Fatalf("open session returned %d: %s", w.Code, w.Body.String())
			}
			done := putChunk(t, e, decodeSession(t, w).SessionID, 0, 3, 4, []byte("abcd"))
			if done.Code != http.StatusOK {
				t.Fatalf("chunk returned %d: %s", done.Code, done.Body.String())
			}
			if got := decodeSession(t, done).Path; got != "notes/clash_(1).bin" {
				t.Errorf("upload reports path %q, want %q", got, "notes/clash_(1).bin")
			}
			assertContents(t, filepath.Join(filesDir, "notes"), map[string]string{
				"clash.bin": "original", "clash_(1).bin": "abcd",
			})
		})
		t.Run(eng.name+"/both choices at once is refused", func(t *testing.T) {
			t.Parallel()
			e, _ := eng.engine(t)
			w := openSession(t, e, map[string]any{
				"fileName": "x.bin", "totalSize": 4, "keepBoth": true, "overwrite": true,
			})
			if w.Code != http.StatusBadRequest {
				t.Fatalf("open session returned %d, want %d: %s", w.Code, http.StatusBadRequest, w.Body.String())
			}
		})
	}
}

// assertContents checks each name in dir against the content it must hold; ""
// means the name must be absent.
func assertContents(t *testing.T, dir string, want map[string]string) {
	t.Helper()
	for name, content := range want {
		got, err := os.ReadFile(filepath.Join(dir, name))
		switch {
		case content == "" && err == nil:
			t.Errorf("%s exists; nothing should have been written there", name)
		case content == "":
		case err != nil:
			t.Errorf("read %s: %v", name, err)
		case string(got) != content:
			t.Errorf("%s holds %q, want %q", name, got, content)
		}
	}
}
