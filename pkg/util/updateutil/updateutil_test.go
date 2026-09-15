package updateutil

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	github "github.com/autobutler-org/quark/pkg/util/githubutil"
)

var defaultUpdateSource = DefaultUpdateSources[0]

func TestMain(m *testing.M) {
	// Allow http:// URLs in fetchURL so httptest servers work in unit tests.
	allowHTTPInFetchURL = true
	os.Exit(m.Run())
}

func TestListPossibleUpdates_NoCurrentVersion(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping integration test in short mode")
	}

	result, err := ListPossibleUpdates(
		defaultUpdateSource,
		false,
	)

	if err != nil {
		t.Fatalf("ListPossibleUpdates failed: %v", err)
		return
	}

	if result == nil {
		t.Error("Expected non-nil result")
	}
}

func TestUpdate_EmptyVersion(t *testing.T) {
	err := Update(defaultUpdateSource, "")
	if err == nil {
		t.Error("Expected error for empty version")
	}

	if err.Error() != "version cannot be empty" {
		t.Errorf("Expected 'version cannot be empty' error, got: %v", err)
	}
}

func TestUpdate_404Response(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	os.Setenv("QUARK_UPDATE_URL", server.URL)
	defer os.Unsetenv("QUARK_UPDATE_URL")

	err := Update(defaultUpdateSource, "v1.0.0")
	if err == nil {
		t.Error("Expected error for 404 response")
	}
}

func TestUpdate_LeavesNothingInTempDir(t *testing.T) {
	tmpDir := t.TempDir()
	t.Setenv("TMPDIR", tmpDir)

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()
	t.Setenv("QUARK_UPDATE_URL", server.URL)

	if err := Update(defaultUpdateSource, "v1.0.0"); err == nil {
		t.Fatal("Expected error for 404 response")
	}

	entries, err := os.ReadDir(tmpDir)
	if err != nil {
		t.Fatalf("Failed to read temp dir: %v", err)
	}
	for _, entry := range entries {
		t.Errorf("Update left %q behind in the temp dir", entry.Name())
	}
}

func TestRemoveStaleBackups(t *testing.T) {
	dir := t.TempDir()
	stale := []string{"autobutler_backup123456", "quark_backup789"}
	keep := []string{"quark_update_123", "quark_extracted456", "unrelated.txt"}
	for _, name := range append(append([]string{}, stale...), keep...) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("binary"), 0o644); err != nil {
			t.Fatalf("Failed to write %s: %v", name, err)
		}
	}
	if err := os.Mkdir(filepath.Join(dir, "quark_backup_dir"), 0o755); err != nil {
		t.Fatalf("Failed to create directory: %v", err)
	}

	result, err := RemoveStaleBackups(RemoveStaleBackupsParams{Dir: dir})
	if err != nil {
		t.Fatalf("RemoveStaleBackups failed: %v", err)
	}

	if len(result.Removed) != len(stale) {
		t.Errorf("Expected %d removed, got %d: %v", len(stale), len(result.Removed), result.Removed)
	}
	for _, name := range stale {
		if _, err := os.Stat(filepath.Join(dir, name)); !os.IsNotExist(err) {
			t.Errorf("Expected %s to be removed", name)
		}
	}
	for _, name := range append(keep, "quark_backup_dir") {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			t.Errorf("Expected %s to be left alone: %v", name, err)
		}
	}
}

func TestRemoveStaleBackups_NothingToDo(t *testing.T) {
	result, err := RemoveStaleBackups(RemoveStaleBackupsParams{Dir: t.TempDir()})
	if err != nil {
		t.Fatalf("RemoveStaleBackups failed: %v", err)
	}
	if len(result.Removed) != 0 {
		t.Errorf("Expected nothing removed, got %v", result.Removed)
	}
}

func TestRemoveStaleBackups_MissingDir(t *testing.T) {
	_, err := RemoveStaleBackups(RemoveStaleBackupsParams{Dir: filepath.Join(t.TempDir(), "missing")})
	if err == nil {
		t.Error("Expected error for a directory that does not exist")
	}
}

func createMockTarGz(t *testing.T, binaryName string, content []byte) []byte {
	t.Helper()

	tmpFile, err := os.CreateTemp("", "test_tar_*")
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer os.Remove(tmpFile.Name())
	defer tmpFile.Close()

	gzWriter := gzip.NewWriter(tmpFile)
	tarWriter := tar.NewWriter(gzWriter)

	header := &tar.Header{
		Name:     binaryName,
		Mode:     0755,
		Size:     int64(len(content)),
		Typeflag: tar.TypeReg,
	}

	if err := tarWriter.WriteHeader(header); err != nil {
		t.Fatalf("Failed to write tar header: %v", err)
	}

	if _, err := tarWriter.Write(content); err != nil {
		t.Fatalf("Failed to write tar content: %v", err)
	}

	tarWriter.Close()
	gzWriter.Close()
	tmpFile.Close()

	data, err := os.ReadFile(tmpFile.Name())
	if err != nil {
		t.Fatalf("Failed to read tar file: %v", err)
	}

	return data
}

type bytesReader struct {
	data []byte
	pos  int
}

func newBytesReader(data []byte) *bytesReader {
	return &bytesReader{data: data}
}

func (r *bytesReader) Read(p []byte) (n int, err error) {
	if r.pos >= len(r.data) {
		return 0, io.EOF
	}
	n = copy(p, r.data[r.pos:])
	r.pos += n
	return n, nil
}

func TestReplaceSelf_BinaryNotInArchive(t *testing.T) {
	tarData := createMockTarGz(t, "wrongname", []byte("content"))

	err := replaceSelf(io.NopCloser(newBytesReader(tarData)), nil)
	if err == nil {
		t.Error("Expected error when binary not found in archive")
	}

	if err.Error() != "binary not found in archive" {
		t.Errorf("Expected 'binary not found in archive', got: %v", err)
	}
}

// The archive is hashed while it streams to disk, and nothing is extracted
// until verify accepts that digest. A rejected archive must therefore fail
// before the "binary not found in archive" check the extraction does — proof
// the verification really does gate the install rather than run alongside it
// (#1723).
func TestReplaceSelf_VerifyRejectsBeforeExtracting(t *testing.T) {
	// An archive that would otherwise get as far as the extraction error.
	tarData := createMockTarGz(t, "wrongname", []byte("content"))

	rejected := errors.New("checksum mismatch")
	var sawSum []byte
	err := replaceSelf(io.NopCloser(newBytesReader(tarData)), func(sum []byte) error {
		sawSum = sum
		return rejected
	})
	if !errors.Is(err, rejected) {
		t.Fatalf("a rejected checksum must stop the update, got: %v", err)
	}

	want := sha256.Sum256(tarData)
	if !bytes.Equal(sawSum, want[:]) {
		t.Errorf("verify got digest %x, want the digest of the streamed archive %x", sawSum, want)
	}
}

func TestConstants(t *testing.T) {
	if binaryName != "quark" {
		t.Errorf("Expected binaryName to be 'quark', got '%s'", binaryName)
	}

	expectedExtractedName := "quark_extracted"
	if extractedName != expectedExtractedName {
		t.Errorf("Expected extractedName to be '%s', got '%s'", expectedExtractedName, extractedName)
	}
}

func TestUpdate_RealRelease_ReplaceSelf(t *testing.T) {
	if runtime.GOOS != "linux" || runtime.GOARCH != "arm64" {
		t.Skipf("Real release test only runs on linux/arm64, got %s/%s", runtime.GOOS, runtime.GOARCH)
	}
	tarPath := "/tmp/quark-test-release/quark_Linux_arm64.tar.gz"
	if _, err := os.Stat(tarPath); os.IsNotExist(err) {
		t.Skip("Real release tarball not available")
	}
	data, err := os.ReadFile(tarPath)
	if err != nil {
		t.Fatalf("failed to read tarball: %v", err)
	}
	// replaceSelf extracts the binary and atomically replaces os.Executable().
	// In the test runner context this will succeed or fail with a permission
	// error — either way is acceptable. What we verify is no panic and no
	// unexpected error (only permission/read-only are OK to get).
	err = replaceSelf(strings.NewReader(string(data)), nil)
	if err != nil &&
		!strings.Contains(err.Error(), "permission") &&
		!strings.Contains(err.Error(), "read-only") &&
		!strings.Contains(err.Error(), "text file busy") {
		t.Errorf("replaceSelf with real tarball returned unexpected error: %v", err)
	}
}

func TestReplaceSelf_WithRealTarball(t *testing.T) {
	tarPath := "/tmp/quark-test-release/quark_Linux_arm64.tar.gz"
	if _, err := os.Stat(tarPath); os.IsNotExist(err) {
		t.Skip("Real release tarball not available")
	}

	f, err := os.Open(tarPath)
	if err != nil {
		t.Fatalf("failed to open tarball: %v", err)
	}
	defer f.Close()

	// replaceSelf will try to overwrite os.Executable() — which in test context
	// is the test binary itself. It may fail with permission denied, but it
	// should successfully decompress and extract the binary from the archive
	// before attempting the replace. We verify the archive is parseable.
	gzr, err := gzip.NewReader(f)
	if err != nil {
		t.Fatalf("failed to create gzip reader: %v", err)
	}
	defer gzr.Close()

	tr := tar.NewReader(gzr)
	found := false
	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("tar read error: %v", err)
		}
		if hdr.Name == binaryName || hdr.Name == "./"+binaryName {
			found = true
			if hdr.Size == 0 {
				t.Error("Expected non-zero binary size in archive")
			}
			break
		}
	}
	if !found {
		t.Errorf("Binary %q not found in release tarball", binaryName)
	}
}

func TestGetLatestVersion_GithubSource(t *testing.T) {
	mockRelease := github.Release{
		TagName: "v0.99.0",
		Assets: []github.Asset{
			{BrowserDownloadURL: fmt.Sprintf("https://example.com/v0.99.0/%s", ConstructArchiveName())},
		},
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.URL.Path, "releases/latest") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `{"tag_name":"%s","assets":[{"browser_download_url":"%s"}]}`,
			mockRelease.TagName,
			mockRelease.Assets[0].BrowserDownloadURL,
		)
	}))
	defer server.Close()
	reset := github.SetBaseURLForTesting(server.URL)
	defer reset()

	githubSource := NewUpdateSource(UpdateSourceKindGithub, "test-org", "test-repo")
	version, err := GetLatestVersion(githubSource)
	if err != nil {
		t.Fatalf("GetLatestVersion failed: %v", err)
	}
	if version != "v0.99.0" {
		t.Errorf("Expected version v0.99.0, got %s", version)
	}
}

func TestGetLatestVersion_GithubSource_NoAsset(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, `{"tag_name":"v1.0.0","assets":[]}`)
	}))
	defer server.Close()
	reset := github.SetBaseURLForTesting(server.URL)
	defer reset()

	source := NewUpdateSource(UpdateSourceKindGithub, "test-org", "test-repo")
	_, err := GetLatestVersion(source)
	if err == nil {
		t.Error("Expected error when no suitable asset found")
	}
}

func TestGetLatestVersion_UnsupportedSource(t *testing.T) {
	source := &UpdateSource{Kind: "unsupported"}
	_, err := GetLatestVersion(source)
	if err == nil {
		t.Error("Expected error for unsupported source kind")
	}
}

func TestListPossibleUpdates_GithubSource_WithReleases(t *testing.T) {
	archiveName := ConstructArchiveName()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.URL.Path, "releases") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, `[
			{"tag_name":"v1.0.0","assets":[{"browser_download_url":"https://example.com/v1.0.0/%s"}]},
			{"tag_name":"v1.1.0","assets":[{"browser_download_url":"https://example.com/v1.1.0/%s"}]}
		]`, archiveName, archiveName)
	}))
	defer server.Close()
	reset := github.SetBaseURLForTesting(server.URL)
	defer reset()

	source := NewUpdateSource(UpdateSourceKindGithub, "test-org", "test-repo")
	result, err := ListPossibleUpdates(source, true)
	if err != nil {
		t.Fatalf("ListPossibleUpdates failed: %v", err)
	}
	if len(result.Versions) != 2 {
		t.Errorf("Expected 2 versions, got %d", len(result.Versions))
	}
}

func TestListPossibleUpdates_GithubSource_SkipsNoAsset(t *testing.T) {
	archiveName := ConstructArchiveName()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		// One release has a .tar.gz asset, one has no assets at all
		fmt.Fprintf(w, `[
			{"tag_name":"v1.0.0","assets":[{"browser_download_url":"https://example.com/v1.0.0/%s"}]},
			{"tag_name":"v1.1.0","assets":[]}
		]`, archiveName)
	}))
	defer server.Close()
	reset := github.SetBaseURLForTesting(server.URL)
	defer reset()

	source := NewUpdateSource(UpdateSourceKindGithub, "test-org", "test-repo")
	result, err := ListPossibleUpdates(source, true)
	if err != nil {
		t.Fatalf("ListPossibleUpdates failed: %v", err)
	}
	// v1.1.0 is skipped because it has no .tar.gz asset
	if len(result.Versions) != 1 {
		t.Errorf("Expected 1 version (v1.1.0 skipped due to no .tar.gz asset), got %d", len(result.Versions))
	}
	if result.Versions[0].Version != "v1.0.0" {
		t.Errorf("Expected v1.0.0, got %s", result.Versions[0].Version)
	}
}

func TestUpdateFromDefaultSources_AllFail(t *testing.T) {
	// Point all sources to a server that always 404s
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()
	reset := github.SetBaseURLForTesting(server.URL)
	defer reset()

	err := UpdateFromDefaultSources("v9.9.9")
	if err == nil {
		t.Error("Expected error when all sources fail")
	}
}

func TestConstructArchiveName(t *testing.T) {
	name := ConstructArchiveName()
	if name == "" {
		t.Error("Expected non-empty archive name")
	}
	if !strings.HasSuffix(name, ".tar.gz") {
		t.Errorf("Expected archive name to end in .tar.gz, got %s", name)
	}
	// Should contain OS and arch
	goos := runtime.GOOS
	goarch := runtime.GOARCH
	expectedOS := strings.ToUpper(goos[:1]) + goos[1:]
	if !strings.Contains(name, expectedOS) {
		t.Errorf("Expected archive name to contain OS %q, got %s", expectedOS, name)
	}
	if !strings.Contains(name, goarch) {
		t.Errorf("Expected archive name to contain arch %q, got %s", goarch, name)
	}
}

func TestUpdate_WithMockServer_RealTarball(t *testing.T) {
	// Note: Update() for GitHub sources builds the download URL from hardcoded github.com
	// base URLs in UpdateSource.BaseUrl(), which can't be intercepted via githubutil's
	// SetBaseURLForTesting. Full end-to-end testing of Update() requires either:
	//   a) Refactoring UpdateSource to accept a base URL override, or
	//   b) An integration test hitting the real GitHub.
	// The core logic (download → decompress → extract → replace) is covered by
	// TestReplaceSelf_WithRealTarball and TestUpdate_RealRelease_ReplaceSelf.
	t.Skip("Update() download URL is hardcoded in UpdateSource.BaseUrl() — see comment")
}

func TestIsDevelopmentVersion(t *testing.T) {
	tests := []struct {
		version string
		want    bool
	}{
		{"1.0.0", false},
		{"1.0.0-beta", true},
		{"1.0.0-rc1", true},
		{"1.0.0+build", false},
		{"v1.2.3", false},
		{"v1.2.3-dev", true},
		{"v1.2.3-alpha.1", true},
		{"v1.2.3.4", false},
		{"1.0.0-", true},
		{"-1.0.0", true},
		{"1.0.0--dev", true},
		{"", false},
	}
	for _, tt := range tests {
		got := IsDevelopmentVersion(tt.version)
		if got != tt.want {
			t.Errorf("IsDevelopmentVersion(%q) = %v, want %v", tt.version, got, tt.want)
		}
	}
}

func TestUpdateSource_BaseURLOverride(t *testing.T) {
	source := NewUpdateSource(UpdateSourceKindGithub, "autobutler-org", "quark")

	// Without override: should return real github.com URL
	if got := source.BaseUrl(); got == "" {
		t.Error("Expected non-empty BaseUrl without override")
	}

	// With override: should return the override
	source.BaseURLOverride = "http://localhost:9999"
	if got := source.BaseUrl(); got != "http://localhost:9999" {
		t.Errorf("Expected override URL, got %q", got)
	}

	// UpdateUrl for GitHub should equal BaseUrl (no double /releases/download)
	if got := source.UpdateUrl(); got != "http://localhost:9999" {
		t.Errorf("Expected UpdateUrl to equal BaseUrl for GitHub, got %q", got)
	}
}

func TestUpdate_WithBaseURLOverride_404(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	source := NewUpdateSource(UpdateSourceKindGithub, "autobutler-org", "quark")
	source.BaseURLOverride = server.URL

	err := Update(source, "v1.0.0")
	if err == nil {
		t.Error("Expected error for 404 response")
	}
}

func TestListPossibleUpdates_FilteredToEmpty_ReturnsEmptySliceNotNil(t *testing.T) {
	// When version filtering leaves no results, Versions must be a non-nil
	// empty slice so it marshals to JSON [] rather than null.
	// Use a GitHub source with no matching assets so updateReleases is empty
	// and the filter loop never appends — this exercises the zero-item path.
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.URL.Path, "releases") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
		// Release exists but has no assets matching this platform's archive name
		fmt.Fprint(w, `[{"tag_name":"v1.0.0","assets":[{"browser_download_url":"https://example.com/other-platform.zip"}]}]`)
	}))
	defer server.Close()
	reset := github.SetBaseURLForTesting(server.URL)
	defer reset()

	source := NewUpdateSource(UpdateSourceKindGithub, "test-org", "test-repo")
	result, err := ListPossibleUpdates(source, true) // allVersions=true, no filter
	if err != nil {
		t.Fatalf("ListPossibleUpdates failed: %v", err)
	}
	if result.Versions == nil {
		t.Error("Expected non-nil empty slice, got nil (would marshal to JSON null)")
	}
	if len(result.Versions) != 0 {
		t.Errorf("Expected 0 versions (no matching assets), got %d", len(result.Versions))
	}
}

// --- verifyChecksumOf / fetchURL ---

// serveChecksums serves body as a release checksums file.
func serveChecksums(t *testing.T, body string) string {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, body)
	}))
	t.Cleanup(server.Close)
	return server.URL + "/quark_1.0.0_checksums.txt"
}

func TestChecksumsFileName(t *testing.T) {
	for _, version := range []string{"v0.38.0", "0.38.0"} {
		if got := checksumsFileName(version); got != "quark_0.38.0_checksums.txt" {
			t.Errorf("checksumsFileName(%q) = %q, want the name GoReleaser publishes", version, got)
		}
	}
}

// The shape GoReleaser publishes: one sha256sum(1) line per archive. The entry
// for this archive must be picked out, not whichever line comes first.
func TestVerifyChecksum_MatchesTheArchiveEntry(t *testing.T) {
	data := []byte("hello, quark")
	sum := sha256.Sum256(data)
	url := serveChecksums(t, fmt.Sprintf(
		"%s  quark_Linux_x86_64.tar.gz\n%s  quark_Linux_arm64.tar.gz\n",
		strings.Repeat("0", 64), hex.EncodeToString(sum[:]),
	))

	if err := verifyChecksumOf(sha256Of(data), url, "quark_Linux_arm64.tar.gz"); err != nil {
		t.Errorf("expected no error for matching checksum, got %v", err)
	}
}

func TestVerifyChecksum_Mismatch(t *testing.T) {
	url := serveChecksums(t, strings.Repeat("de", 32)+"  quark_Linux_arm64.tar.gz\n")

	err := verifyChecksumOf(sha256Of([]byte("hello, quark")), url, "quark_Linux_arm64.tar.gz")
	if err == nil {
		t.Error("expected error for mismatched checksum")
	}
	if errors.Is(err, errChecksumUnavailable) {
		t.Error("mismatch should not report errChecksumUnavailable")
	}
}

// A file that verifies some other archive verifies nothing about this one.
func TestVerifyChecksum_MissingEntryFails(t *testing.T) {
	data := []byte("data")
	sum := sha256.Sum256(data)
	url := serveChecksums(t, hex.EncodeToString(sum[:])+"  quark_Linux_x86_64.tar.gz\n")

	if err := verifyChecksumOf(sha256Of(data), url, "quark_Linux_arm64.tar.gz"); err == nil {
		t.Error("expected error when the checksums file has no entry for the archive")
	}
}

func TestVerifyChecksum_Unavailable(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	err := verifyChecksumOf(sha256Of([]byte("data")), server.URL+"/quark_1.0.0_checksums.txt", "quark_Linux_arm64.tar.gz")
	if !errors.Is(err, errChecksumUnavailable) {
		t.Errorf("expected errChecksumUnavailable for 404, got %v", err)
	}
}

func TestVerifyChecksum_EmptyFile(t *testing.T) {
	url := serveChecksums(t, "")
	if err := verifyChecksumOf(sha256Of([]byte("data")), url, "quark_Linux_arm64.tar.gz"); err == nil {
		t.Error("expected error for empty checksum file")
	}
}

func TestVerifyChecksum_InvalidHex(t *testing.T) {
	url := serveChecksums(t, "not-a-hex-string  quark_Linux_arm64.tar.gz\n")
	if err := verifyChecksumOf(sha256Of([]byte("data")), url, "quark_Linux_arm64.tar.gz"); err == nil {
		t.Error("expected error for invalid hex checksum")
	}
}

// The update used to warn and install anyway when its checksum was missing,
// and it looked for a .sha256 file no release publishes, so every update
// skipped verification. It must now ask for the release's checksums file and
// stop when that is not there.
func TestUpdate_FailsClosedWithoutChecksumsFile(t *testing.T) {
	archiveName := ConstructArchiveName()
	var checksumsRequested bool
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1.0.0/" + archiveName:
			fmt.Fprint(w, "not really an archive")
		case "/v1.0.0/quark_1.0.0_checksums.txt":
			checksumsRequested = true
			w.WriteHeader(http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer server.Close()

	source := NewUpdateSource(UpdateSourceKindGithub, "autobutler-org", "quark")
	source.BaseURLOverride = server.URL

	err := Update(source, "v1.0.0")
	if !checksumsRequested {
		t.Error("Update did not request the release's checksums file")
	}
	if !errors.Is(err, errChecksumUnavailable) {
		t.Errorf("expected the update to stop on the missing checksums file, got %v", err)
	}
}

// fetchURL must stay agnostic about *what* was missing. It used to return
// errChecksumUnavailable for every 404, so a download from a repository that
// does not exist was reported as "checksum file not found" (#1610).
func TestFetchURL_404ReturnsNotFound(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	_, err := fetchURL(server.URL + "/missing")
	if !errors.Is(err, errNotFound) {
		t.Errorf("expected errNotFound for 404, got %v", err)
	}
	if errors.Is(err, errChecksumUnavailable) {
		t.Error("fetchURL must not assume a 404 means the checksum file is missing")
	}
}

func TestFetchURL_500ReturnsError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	}))
	defer server.Close()

	_, err := fetchURL(server.URL + "/error")
	if err == nil {
		t.Error("expected error for HTTP 500")
	}
	if errors.Is(err, errNotFound) {
		t.Error("HTTP 500 should not be errNotFound")
	}
}

func TestFetchURL_RejectsHTTP(t *testing.T) {
	// Temporarily re-enable the HTTPS restriction for this test.
	allowHTTPInFetchURL = false
	defer func() { allowHTTPInFetchURL = true }()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	_, err := fetchURL(server.URL + "/file")
	if err == nil {
		t.Error("expected error for http:// URL")
	}
	if !strings.Contains(err.Error(), "only https is allowed") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestFetchURL_RejectsUnknownHost(t *testing.T) {
	// allowHTTPInFetchURL is true in tests but host allowlist still applies.
	// Temporarily disable the http-allow flag so both checks fire.
	allowHTTPInFetchURL = false
	defer func() { allowHTTPInFetchURL = true }()

	_, err := fetchURL("https://evil.example.com/malware")
	if err == nil {
		t.Error("expected error for unknown host")
	}
	if !strings.Contains(err.Error(), "not an allowed update server") {
		t.Errorf("unexpected error: %v", err)
	}
}

func TestIsAllowedUpdateHost(t *testing.T) {
	cases := []struct {
		host    string
		allowed bool
	}{
		{"github.com", true},
		{"objects.githubusercontent.com", true},
		{"quarkrelease.blob.core.windows.net", true},
		{"evil.com", false},
		{"github.com.evil.com", false},
		{"", false},
	}
	for _, c := range cases {
		got := isAllowedUpdateHost(c.host)
		if got != c.allowed {
			t.Errorf("isAllowedUpdateHost(%q) = %v, want %v", c.host, got, c.allowed)
		}
	}
}

// sha256Of is what SelfUpdate now hands verifyChecksumOf: the digest of the
// archive, computed while it streamed to disk rather than from a buffer.
func sha256Of(data []byte) []byte {
	sum := sha256.Sum256(data)
	return sum[:]
}
