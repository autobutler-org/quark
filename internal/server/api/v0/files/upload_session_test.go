package v0_files_test

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"net/http/httptest"
	"os"
	"path"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/gin-gonic/gin"
)

// Resumable chunked uploads (#1629). The endpoint exists so a multi-gigabyte
// file survives a dropped connection, so most of what is worth testing is what
// happens when things go wrong halfway: a stale offset, a replayed chunk, a
// session that expired. The one happy path that matters is the big one — the
// bytes have to come out the far end identical, which a file of zeroes would
// not prove.
const (
	// largeUploadSize is comfortably more than one chunk, so the reassembly is
	// exercised rather than assumed. Kept modest enough to stay fast; what
	// makes the test meaningful is the number of chunks, not the megabytes.
	largeUploadSize = 20 << 20
	// uploadChunkSize matches the 8 MiB the client uses.
	uploadChunkSize = 8 << 20
)

type sessionResponse struct {
	SessionID string    `json:"sessionId"`
	Offset    int64     `json:"offset"`
	TotalSize int64     `json:"totalSize"`
	FileName  string    `json:"fileName"`
	RootDir   string    `json:"rootDir"`
	Complete  bool      `json:"complete"`
	Path      string    `json:"path"`
	ExpiresAt time.Time `json:"expiresAt"`
}

// newUploadSessionEngine wires the same VFS-backed engine the other upload
// tests use, and hands back the session store so a test can sweep it or look at
// what it left on disk.
func newUploadSessionEngine(t *testing.T) (*gin.Engine, string, *uploadutil.SessionStore) {
	t.Helper()
	deps, filesDir := newStorageVFSDeps(t)
	return newEngineForDeps(deps), filesDir, deps.UploadSessions()
}

// randomContent is a seeded pseudo-random stream. Deterministic so a failure
// reproduces, and non-uniform so a chunk written at the wrong offset changes
// the hash — a buffer of zeroes would pass an implementation that reassembles
// the file in the wrong order.
func randomContent(t *testing.T, size int) []byte {
	t.Helper()
	const seed = 1629
	buf := make([]byte, size)
	if _, err := rand.New(rand.NewSource(seed)).Read(buf); err != nil {
		t.Fatalf("failed to generate upload content: %v", err)
	}
	return buf
}

func sha256Hex(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// sha256File hashes the uploaded file without holding a second copy of it in
// memory alongside the source.
func sha256File(t *testing.T, path string) string {
	t.Helper()
	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("open %s: %v", path, err)
	}
	defer f.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, f); err != nil {
		t.Fatalf("hash %s: %v", path, err)
	}
	return hex.EncodeToString(digest.Sum(nil))
}

func openSession(t *testing.T, engine *gin.Engine, body map[string]any) *httptest.ResponseRecorder {
	t.Helper()
	encoded, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("encode session request: %v", err)
	}
	return doRequest(engine, http.MethodPost, "/api/v0/files/upload-session",
		bytes.NewReader(encoded), "application/json")
}

// openSessionOK opens a session for a file of totalSize bytes and fails the
// test if the server refuses.
func openSessionOK(t *testing.T, engine *gin.Engine, rootDir, fileName string, totalSize int) string {
	t.Helper()
	w := openSession(t, engine, map[string]any{
		"rootDir":   rootDir,
		"fileName":  fileName,
		"totalSize": totalSize,
	})
	if w.Code != http.StatusOK {
		t.Fatalf("open session returned %d: %s", w.Code, w.Body.String())
	}
	decoded := decodeSession(t, w)
	if decoded.SessionID == "" {
		t.Fatal("open session returned an empty session id")
	}
	if decoded.Offset != 0 {
		t.Fatalf("a new session starts at offset %d, want 0", decoded.Offset)
	}
	return decoded.SessionID
}

// putChunk sends body as the bytes at [start, start+len(body)) of a file of
// totalSize bytes. declaredEnd exists so a test can lie about the range.
func putChunk(
	t *testing.T,
	engine *gin.Engine,
	sessionID string,
	start, declaredEnd, totalSize int,
	body []byte,
) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPut,
		"/api/v0/files/upload-session/"+sessionID, bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, declaredEnd, totalSize))
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// putSlice sends content[start:end] as the chunk covering exactly that range.
func putSlice(
	t *testing.T,
	engine *gin.Engine,
	sessionID string,
	content []byte,
	start, end int,
) *httptest.ResponseRecorder {
	t.Helper()
	return putChunk(t, engine, sessionID, start, end-1, len(content), content[start:end])
}

func getSession(t *testing.T, engine *gin.Engine, sessionID string) *httptest.ResponseRecorder {
	t.Helper()
	return doRequest(engine, http.MethodGet, "/api/v0/files/upload-session/"+sessionID, nil, "")
}

func decodeSession(t *testing.T, w *httptest.ResponseRecorder) sessionResponse {
	t.Helper()
	var decoded sessionResponse
	if err := json.Unmarshal(w.Body.Bytes(), &decoded); err != nil {
		t.Fatalf("decode session response: %v\nbody: %s", err, w.Body.String())
	}
	return decoded
}

// uploadInChunks sends the whole file in chunkSize slices and returns the final
// response.
func uploadInChunks(
	t *testing.T,
	engine *gin.Engine,
	sessionID string,
	content []byte,
	chunkSize int,
) *httptest.ResponseRecorder {
	t.Helper()
	var last *httptest.ResponseRecorder
	for start := 0; start < len(content); start += chunkSize {
		end := min(start+chunkSize, len(content))
		last = putSlice(t, engine, sessionID, content, start, end)
		if last.Code != http.StatusOK {
			t.Fatalf("chunk [%d,%d) returned %d: %s", start, end, last.Code, last.Body.String())
		}
	}
	return last
}

// The route the contract asked for — POST /files/upload/session — cannot be
// registered: gin's group prefix and route path go through path.Join, which
// collapses the deliberate double slash in "/files//upload/*rootDir" into a
// catch-all at /api/v0/files/upload/, and a static child under a catch-all
// panics at startup. This test is the reason the endpoints live at
// /files/upload-session instead, and it fails loudly if anyone moves them back.
func TestUploadSessionRoutesRegisterWithoutConflict(t *testing.T) {
	t.Parallel()

	engine, _, _ := newUploadSessionEngine(t)

	registered := make(map[string]bool)
	for _, route := range engine.Routes() {
		registered[route.Method+" "+route.Path] = true
	}
	for _, want := range []string{
		"POST /api/v0/files/upload-session",
		"PUT /api/v0/files/upload-session/:sessionId",
		"GET /api/v0/files/upload-session/:sessionId",
		"DELETE /api/v0/files/upload-session/:sessionId",
		// The multipart endpoint the small-file path still uses.
		"POST /api/v0/files/upload",
	} {
		if !registered[want] {
			t.Errorf("route %q is not registered", want)
		}
	}
}

// The headline case: a file too big for one request goes up in chunks and comes
// out byte for byte identical, at the path rootDir put it.
func TestResumableUploadOfALargeFileIsByteForByte(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	content := randomContent(t, largeUploadSize)

	const rootDir = "videos/2024"
	sessionID := openSessionOK(t, engine, rootDir, "clip.mp4", len(content))
	final := decodeSession(t, uploadInChunks(t, engine, sessionID, content, uploadChunkSize))

	if !final.Complete {
		t.Fatalf("the last chunk did not complete the upload: %+v", final)
	}
	if final.Offset != int64(len(content)) {
		t.Errorf("final offset is %d, want %d", final.Offset, len(content))
	}
	if want := path.Join(rootDir, "clip.mp4"); final.Path != want {
		t.Errorf("upload reports path %q, want %q", final.Path, want)
	}

	uploaded := filepath.Join(filesDir, "videos", "2024", "clip.mp4")
	if got, want := sha256File(t, uploaded), sha256Hex(content); got != want {
		t.Errorf("uploaded file hashes to %s, want %s", got, want)
	}

	// A completed session is gone; the client has no reason to hold it.
	if w := getSession(t, engine, sessionID); w.Code != http.StatusNotFound {
		t.Errorf("completed session returned %d, want %d", w.Code, http.StatusNotFound)
	}
}

// Resume as the client actually does it: send some chunks, lose track, ask what
// landed, carry on from there.
func TestResumableUploadContinuesFromTheReportedOffset(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	content := randomContent(t, largeUploadSize)
	sessionID := openSessionOK(t, engine, "", "resume.bin", len(content))

	const committedChunks = 2
	for i := range committedChunks {
		start := i * uploadChunkSize
		if w := putSlice(t, engine, sessionID, content, start, start+uploadChunkSize); w.Code != http.StatusOK {
			t.Fatalf("chunk %d returned %d: %s", i, w.Code, w.Body.String())
		}
	}

	status := decodeSession(t, getSession(t, engine, sessionID))
	if want := int64(committedChunks * uploadChunkSize); status.Offset != want {
		t.Fatalf("session reports offset %d, want %d", status.Offset, want)
	}
	if status.TotalSize != int64(len(content)) || status.FileName != "resume.bin" {
		t.Errorf("session describes itself as %+v", status)
	}

	for start := int(status.Offset); start < len(content); start += uploadChunkSize {
		end := min(start+uploadChunkSize, len(content))
		if w := putSlice(t, engine, sessionID, content, start, end); w.Code != http.StatusOK {
			t.Fatalf("resumed chunk [%d,%d) returned %d: %s", start, end, w.Code, w.Body.String())
		}
	}

	if got, want := sha256File(t, filepath.Join(filesDir, "resume.bin")), sha256Hex(content); got != want {
		t.Errorf("resumed upload hashes to %s, want %s", got, want)
	}
}

// The connection died between the server committing a chunk and the client
// hearing about it, so the client resends from an offset that is behind the
// truth. It must be told the real one, and be able to finish from there.
func TestResumableUploadRejectsAStaleOffsetAndResyncs(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	content := randomContent(t, largeUploadSize)
	sessionID := openSessionOK(t, engine, "", "flaky.bin", len(content))

	if w := putSlice(t, engine, sessionID, content, 0, uploadChunkSize); w.Code != http.StatusOK {
		t.Fatalf("first chunk returned %d: %s", w.Code, w.Body.String())
	}

	// The client lost its bookkeeping and restarted with a different chunk
	// size, so it offers bytes that straddle the committed offset. Appending
	// that would duplicate what is already there.
	stale := putSlice(t, engine, sessionID, content, 0, uploadChunkSize+(1<<20))
	if stale.Code != http.StatusConflict {
		t.Fatalf("stale chunk returned %d, want %d: %s", stale.Code, http.StatusConflict, stale.Body.String())
	}
	if got, want := stale.Header().Get("X-Upload-Offset"), strconv.Itoa(uploadChunkSize); got != want {
		t.Fatalf("conflict reported offset %q, want %q", got, want)
	}

	status := decodeSession(t, getSession(t, engine, sessionID))
	for start := int(status.Offset); start < len(content); start += uploadChunkSize {
		end := min(start+uploadChunkSize, len(content))
		if w := putSlice(t, engine, sessionID, content, start, end); w.Code != http.StatusOK {
			t.Fatalf("chunk [%d,%d) after resync returned %d: %s", start, end, w.Code, w.Body.String())
		}
	}

	if got, want := sha256File(t, filepath.Join(filesDir, "flaky.bin")), sha256Hex(content); got != want {
		t.Errorf("upload hashes to %s, want %s", got, want)
	}
}

// The other half of a lost response: the chunk was committed and the client
// retries the whole of it. Answering 409 there would strand a client doing
// exactly the right thing, so the replay is accepted and written nowhere.
func TestResumableUploadAcceptsAReplayedChunk(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	content := randomContent(t, largeUploadSize)
	sessionID := openSessionOK(t, engine, "", "replayed.bin", len(content))

	if w := putSlice(t, engine, sessionID, content, 0, uploadChunkSize); w.Code != http.StatusOK {
		t.Fatalf("first chunk returned %d: %s", w.Code, w.Body.String())
	}
	replay := putSlice(t, engine, sessionID, content, 0, uploadChunkSize)
	if replay.Code != http.StatusOK {
		t.Fatalf("replayed chunk returned %d, want %d: %s", replay.Code, http.StatusOK, replay.Body.String())
	}
	if got := decodeSession(t, replay).Offset; got != uploadChunkSize {
		t.Fatalf("replay moved the offset to %d, want %d", got, uploadChunkSize)
	}

	for start := uploadChunkSize; start < len(content); start += uploadChunkSize {
		end := min(start+uploadChunkSize, len(content))
		if w := putSlice(t, engine, sessionID, content, start, end); w.Code != http.StatusOK {
			t.Fatalf("chunk [%d,%d) returned %d: %s", start, end, w.Code, w.Body.String())
		}
	}

	// The replay must not have shifted anything: the file is still exact.
	if got, want := sha256File(t, filepath.Join(filesDir, "replayed.bin")), sha256Hex(content); got != want {
		t.Errorf("upload hashes to %s, want %s after a replayed chunk", got, want)
	}
}

// A chunk that starts past the committed offset would leave a hole. The server
// appends and never seeks, so it refuses and says where it actually is.
func TestResumableUploadRejectsAGap(t *testing.T) {
	t.Parallel()

	engine, _, _ := newUploadSessionEngine(t)
	content := randomContent(t, 4096)
	sessionID := openSessionOK(t, engine, "", "gap.bin", len(content))

	w := putSlice(t, engine, sessionID, content, 1024, 2048)
	if w.Code != http.StatusConflict {
		t.Fatalf("chunk past the offset returned %d, want %d: %s", w.Code, http.StatusConflict, w.Body.String())
	}
	if got := w.Header().Get("X-Upload-Offset"); got != "0" {
		t.Errorf("conflict reported offset %q, want %q", got, "0")
	}
}

// Everything the server cannot place is a 400: it knows what it holds, and a
// client that cannot say which bytes it is sending has nothing to commit.
func TestResumableUploadRejectsUnusableChunks(t *testing.T) {
	t.Parallel()

	const totalSize = 4096

	cases := []struct {
		name         string
		contentRange string
		body         []byte
	}{
		{name: "missing content range", contentRange: "", body: make([]byte, 16)},
		{name: "not a byte range", contentRange: "chunks 0-15/4096", body: make([]byte, 16)},
		{name: "no total size", contentRange: "bytes 0-15", body: make([]byte, 16)},
		{name: "unparseable bounds", contentRange: "bytes a-b/4096", body: make([]byte, 16)},
		{name: "end before start", contentRange: "bytes 15-0/4096", body: nil},
		{name: "end past the total", contentRange: "bytes 0-4096/4096", body: make([]byte, 4097)},
		{name: "total contradicts the session", contentRange: "bytes 0-15/8192", body: make([]byte, 16)},
		{name: "body shorter than the range", contentRange: "bytes 0-15/4096", body: make([]byte, 8)},
		{name: "body longer than the range", contentRange: "bytes 0-15/4096", body: make([]byte, 32)},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			engine, _, _ := newUploadSessionEngine(t)
			sessionID := openSessionOK(t, engine, "", "bad.bin", totalSize)

			req := httptest.NewRequest(http.MethodPut,
				"/api/v0/files/upload-session/"+sessionID, bytes.NewReader(tc.body))
			if tc.contentRange != "" {
				req.Header.Set("Content-Range", tc.contentRange)
			}
			w := httptest.NewRecorder()
			engine.ServeHTTP(w, req)

			if w.Code != http.StatusBadRequest {
				t.Fatalf("returned %d, want %d: %s", w.Code, http.StatusBadRequest, w.Body.String())
			}
			// Nothing was committed, so the session is still usable.
			if got := decodeSession(t, getSession(t, engine, sessionID)).Offset; got != 0 {
				t.Errorf("a rejected chunk moved the offset to %d", got)
			}
		})
	}
}

// A session the server does not have is a 404 on every verb, and the client's
// only recourse is a new session from zero — which is also what it sees after a
// server restart, since sessions live in memory.
func TestUnknownUploadSessionIsNotFound(t *testing.T) {
	t.Parallel()

	engine, _, _ := newUploadSessionEngine(t)
	const unknown = "0123456789abcdef0123456789abcdef"

	if w := putChunk(t, engine, unknown, 0, 15, 4096, make([]byte, 16)); w.Code != http.StatusNotFound {
		t.Errorf("PUT to an unknown session returned %d, want %d", w.Code, http.StatusNotFound)
	}
	if w := getSession(t, engine, unknown); w.Code != http.StatusNotFound {
		t.Errorf("GET of an unknown session returned %d, want %d", w.Code, http.StatusNotFound)
	}
	w := doRequest(engine, http.MethodDelete, "/api/v0/files/upload-session/"+unknown, nil, "")
	if w.Code != http.StatusNotFound {
		t.Errorf("DELETE of an unknown session returned %d, want %d", w.Code, http.StatusNotFound)
	}
}

// The invariant the whole staging dance exists for: half a file must never be
// visible as a real file. A client listing the folder mid-upload sees nothing,
// and nothing partial is on disk under the target name either.
func TestPartialUploadIsNeverVisibleAsAFile(t *testing.T) {
	t.Parallel()

	engine, filesDir, _ := newUploadSessionEngine(t)
	content := randomContent(t, largeUploadSize)

	const rootDir = "incoming"
	sessionID := openSessionOK(t, engine, rootDir, "half.bin", len(content))
	if w := putSlice(t, engine, sessionID, content, 0, uploadChunkSize); w.Code != http.StatusOK {
		t.Fatalf("first chunk returned %d: %s", w.Code, w.Body.String())
	}

	// Nothing is listable under the target name — and since the destination
	// directory is not created until the commit either, the folder itself is
	// still absent.
	for _, node := range listFiles(t, engine, "") {
		if name, _ := node["name"].(string); strings.Contains(name, "half.bin") {
			t.Errorf("a partial upload is listed as %q", name)
		}
	}
	listing := doRequest(engine, http.MethodGet, "/api/v0/files?rootDir="+rootDir, nil, "")
	if listing.Code == http.StatusOK {
		for _, node := range decodeFilePaths(t, listing.Body.Bytes()) {
			t.Errorf("a partial upload put %q in the destination folder", node)
		}
	}
	if _, err := os.Stat(filepath.Join(filesDir, rootDir, "half.bin")); !os.IsNotExist(err) {
		t.Errorf("a partial upload exists on disk: %v", err)
	}

	// It appears the moment the last byte lands, and not before.
	uploadInChunks(t, engine, sessionID, content, uploadChunkSize)
	assertFileExists(t, filepath.Join(filesDir, rootDir, "half.bin"))
}

// An abandoned upload holds its staged bytes until something takes them back.
// Sweep is called directly rather than waiting out a TTL.
func TestSweepExpiresSessionsAndDeletesStagedBytes(t *testing.T) {
	t.Parallel()

	engine, _, store := newUploadSessionEngine(t)
	content := randomContent(t, 4096)
	sessionID := openSessionOK(t, engine, "", "abandoned.bin", len(content))
	if w := putSlice(t, engine, sessionID, content, 0, 1024); w.Code != http.StatusOK {
		t.Fatalf("chunk returned %d: %s", w.Code, w.Body.String())
	}
	if got := stagedFileCount(t, store.StagingDir()); got != 1 {
		t.Fatalf("expected 1 staged file before the sweep, found %d", got)
	}

	if result := store.Sweep(time.Now().Add(2 * uploadutil.DefaultSessionTTL)); result.Expired != 1 {
		t.Fatalf("sweep expired %d sessions, want 1", result.Expired)
	}
	if w := getSession(t, engine, sessionID); w.Code != http.StatusNotFound {
		t.Errorf("a swept session returned %d, want %d", w.Code, http.StatusNotFound)
	}
	if got := stagedFileCount(t, store.StagingDir()); got != 0 {
		t.Errorf("sweep left %d staged file(s) behind", got)
	}
}

// Cancelling from the client gives the disk back immediately instead of at the
// TTL.
func TestDeleteUploadSessionRemovesStagedBytes(t *testing.T) {
	t.Parallel()

	engine, _, store := newUploadSessionEngine(t)
	content := randomContent(t, 4096)
	sessionID := openSessionOK(t, engine, "", "cancelled.bin", len(content))
	if w := putSlice(t, engine, sessionID, content, 0, 1024); w.Code != http.StatusOK {
		t.Fatalf("chunk returned %d: %s", w.Code, w.Body.String())
	}

	w := doRequest(engine, http.MethodDelete, "/api/v0/files/upload-session/"+sessionID, nil, "")
	if w.Code != http.StatusOK {
		t.Fatalf("delete returned %d: %s", w.Code, w.Body.String())
	}
	if got := stagedFileCount(t, store.StagingDir()); got != 0 {
		t.Errorf("delete left %d staged file(s) behind", got)
	}
	if w := getSession(t, engine, sessionID); w.Code != http.StatusNotFound {
		t.Errorf("a deleted session returned %d, want %d", w.Code, http.StatusNotFound)
	}
}

// A re-upload of a file that already landed — what a client does when its
// final chunk timed out after the server committed — can never commit without
// overwrite. The 400 ends the session, so the second copy is not kept on disk
// for a day.
func TestAConflictingCommitEndsTheSessionAndDeletesStagedBytes(t *testing.T) {
	t.Parallel()

	engine, _, store := newUploadSessionEngine(t)
	content := randomContent(t, 4096)
	first := openSessionOK(t, engine, "", "twice.bin", len(content))
	uploadInChunks(t, engine, first, content, 1024)

	second := openSessionOK(t, engine, "", "twice.bin", len(content))
	for start := 0; start < 3072; start += 1024 {
		if w := putSlice(t, engine, second, content, start, start+1024); w.Code != http.StatusOK {
			t.Fatalf("chunk at %d returned %d: %s", start, w.Code, w.Body.String())
		}
	}
	if w := putSlice(t, engine, second, content, 3072, 4096); w.Code != http.StatusBadRequest {
		t.Fatalf("commit over an existing file returned %d, want %d: %s", w.Code, http.StatusBadRequest, w.Body.String())
	}
	if got := stagedFileCount(t, store.StagingDir()); got != 0 {
		t.Errorf("a refused commit left %d staged file(s) behind", got)
	}
	if w := putSlice(t, engine, second, content, 3072, 4096); w.Code != http.StatusNotFound {
		t.Errorf("retrying an ended session returned %d, want %d", w.Code, http.StatusNotFound)
	}
}

func stagedFileCount(t *testing.T, stagingDir string) int {
	t.Helper()
	entries, err := os.ReadDir(stagingDir)
	if os.IsNotExist(err) {
		return 0
	}
	if err != nil {
		t.Fatalf("read staging dir %s: %v", stagingDir, err)
	}
	return len(entries)
}

// The same invariants upload_files_test.go pins for the multipart endpoint
// (#1603): structure travels in rootDir, the filename is flattened to its
// basename, and neither can climb out of the upload root.
func TestUploadSessionKeepsTheTraversalInvariants(t *testing.T) {
	t.Parallel()

	t.Run("a rootDir that escapes is refused", func(t *testing.T) {
		t.Parallel()
		engine, filesDir, _ := newUploadSessionEngine(t)
		w := openSession(t, engine, map[string]any{
			"rootDir":   "../../escape",
			"fileName":  "loot.txt",
			"totalSize": 16,
		})
		if w.Code != http.StatusBadRequest {
			t.Fatalf("escaping rootDir returned %d, want %d: %s", w.Code, http.StatusBadRequest, w.Body.String())
		}
		outside := filepath.Join(filepath.Dir(filepath.Dir(filesDir)), "escape")
		if _, err := os.Stat(outside); err == nil {
			t.Errorf("the refused session still created %s", outside)
		}
	})

	t.Run("a nested fileName lands at the root as its basename", func(t *testing.T) {
		t.Parallel()
		engine, filesDir, _ := newUploadSessionEngine(t)
		content := randomContent(t, 4096)
		sessionID := openSessionOK(t, engine, "", "notes/meeting.txt", len(content))
		final := decodeSession(t, uploadInChunks(t, engine, sessionID, content, 1024))

		if final.Path != "meeting.txt" {
			t.Errorf("upload reports path %q, want %q", final.Path, "meeting.txt")
		}
		assertFileExists(t, filepath.Join(filesDir, "meeting.txt"))
		if _, err := os.Stat(filepath.Join(filesDir, "notes")); err == nil {
			t.Errorf("the directory in the filename was honored instead of stripped")
		}
	})
}

// A session that cannot describe a real file is refused before a byte is
// staged, rather than after gigabytes have been written.
func TestOpenUploadSessionRejectsAnUndescribableFile(t *testing.T) {
	t.Parallel()

	cases := []struct {
		name string
		body map[string]any
	}{
		{name: "no file name", body: map[string]any{"fileName": "", "totalSize": 16}},
		{name: "file name is only a separator", body: map[string]any{"fileName": "/", "totalSize": 16}},
		{name: "file name is only a traversal", body: map[string]any{"fileName": "..", "totalSize": 16}},
		{name: "zero total size", body: map[string]any{"fileName": "empty.bin", "totalSize": 0}},
		{name: "negative total size", body: map[string]any{"fileName": "odd.bin", "totalSize": -1}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			engine, _, store := newUploadSessionEngine(t)
			w := openSession(t, engine, tc.body)
			if w.Code != http.StatusBadRequest {
				t.Fatalf("returned %d, want %d: %s", w.Code, http.StatusBadRequest, w.Body.String())
			}
			if got := stagedFileCount(t, store.StagingDir()); got != 0 {
				t.Errorf("a refused session staged %d file(s)", got)
			}
		})
	}
}

// Sessions are for big files. A small one still goes as a single multipart
// request, and adding the session endpoints must not have disturbed that.
func TestSmallFileStillUploadsInOneMultipartRequest(t *testing.T) {
	t.Parallel()

	engine, filesDir, store := newUploadSessionEngine(t)
	w := uploadFile(t, engine, "/api/v0/files/upload/notes", "small.txt", "still one request")
	if w.Code != http.StatusOK {
		t.Fatalf("multipart upload returned %d: %s", w.Code, w.Body.String())
	}
	assertFileExists(t, filepath.Join(filesDir, "notes", "small.txt"))
	if got := stagedFileCount(t, store.StagingDir()); got != 0 {
		t.Errorf("a multipart upload staged %d session file(s)", got)
	}
}

// A file with a serial named on it has no VFS namespace to land in and takes
// the StorageService instead. Both destinations have to reassemble the chunks
// the same way.
func TestResumableUploadThroughTheStorageService(t *testing.T) {
	t.Parallel()

	engine, filesDir := newTestEngine(t)
	content := randomContent(t, 5<<20)

	w := openSession(t, engine, map[string]any{
		"rootDir":   "clips",
		"fileName":  "no-vfs.bin",
		"totalSize": len(content),
	})
	if w.Code != http.StatusOK {
		t.Fatalf("open session returned %d: %s", w.Code, w.Body.String())
	}
	sessionID := decodeSession(t, w).SessionID

	const chunkSize = 1 << 20
	final := decodeSession(t, uploadInChunks(t, engine, sessionID, content, chunkSize))
	if !final.Complete {
		t.Fatalf("the last chunk did not complete the upload: %+v", final)
	}
	if got, want := sha256File(t, filepath.Join(filesDir, "clips", "no-vfs.bin")), sha256Hex(content); got != want {
		t.Errorf("upload hashes to %s, want %s", got, want)
	}
}

// deputil.NewDependencies gives every dependency graph a store, so no test
// engine has to be edited to get one — and nothing in the constructor touches
// disk or starts a goroutine.
func TestNewDependenciesCarriesAnUploadSessionStore(t *testing.T) {
	t.Parallel()

	if deputil.NewDependencies().UploadSessions() == nil {
		t.Fatal("NewDependencies left the upload session store nil")
	}
}
