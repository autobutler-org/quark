package updateutil

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"os/user"
	"path/filepath"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
)

func init() {
	var err error
	client, err = azblob.NewClientWithNoCredential(DefaultUpdateSources[0].BaseUrl(), nil)
	if err != nil {
		panic(fmt.Sprintf("Failed to create Azure Blob client: %v", err))
	}
}

// maxMetadataBytes caps what fetchURL will hold in memory. It only ever
// retrieves a release's checksums file — one short line per archive — while
// the release archive itself goes through fetchStream and is never buffered.
const maxMetadataBytes = 64 * 1024

// fetchURL performs a GET and returns the response body as bytes, refusing
// anything larger than maxMetadataBytes. Use it for small companion files
// only; fetchStream is what a release archive travels on (#1723).
func fetchURL(rawURL string) ([]byte, error) {
	body, err := fetchStream(rawURL)
	if err != nil {
		return nil, err
	}
	defer body.Close()

	data, err := io.ReadAll(io.LimitReader(body, maxMetadataBytes+1))
	if err != nil {
		return nil, err
	}
	if len(data) > maxMetadataBytes {
		return nil, fmt.Errorf("response from %s exceeds %d bytes", rawURL, maxMetadataBytes)
	}
	return data, nil
}

// fetchStream performs a GET and returns the response body for the caller to
// stream. Only HTTPS connections to known update hosts are allowed. Returns
// errNotFound on HTTP 404; other non-200 responses return a descriptive error.
// The caller owns the returned ReadCloser.
func fetchStream(rawURL string) (io.ReadCloser, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}
	if parsed.Scheme != "https" && !allowHTTPInFetchURL {
		return nil, fmt.Errorf("insecure URL scheme %q: only https is allowed for downloads", parsed.Scheme)
	}

	// Validate host and replace it with the canonical allowlist value so the
	// request URL is constructed from a compile-time constant, not user input.
	// This breaks the taint flow that CodeQL's SSRF rule tracks.
	canonicalHost, ok := canonicalUpdateHost(parsed.Hostname())
	if !ok && !allowHTTPInFetchURL {
		return nil, fmt.Errorf("host %q is not an allowed update server", parsed.Hostname())
	}

	// Build the request URL from the allowlist-sourced host (untainted) plus
	// the path/query from the parsed input.
	scheme := "https"
	if allowHTTPInFetchURL && parsed.Scheme == "http" {
		scheme = "http"
	}
	var requestHost string
	if ok {
		// Use the canonical constant from the allowlist — not the user-supplied value.
		requestHost = canonicalHost
		if parsed.Port() != "" {
			requestHost = canonicalHost + ":" + parsed.Port()
		}
	} else {
		// allowHTTPInFetchURL path (tests only): use the raw host as-is.
		requestHost = parsed.Host
	}
	safeURL := &url.URL{
		Scheme:   scheme,
		Host:     requestHost,
		Path:     parsed.EscapedPath(),
		RawQuery: parsed.RawQuery,
	}
	req, err := http.NewRequest(http.MethodGet, safeURL.String(), nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}
	// URL is safe: scheme enforced to https, host validated against an explicit
	// allowlist and replaced with the matching compile-time constant, path and
	// query are URL-encoded release asset components. go/ssrf is excluded in
	// .github/codeql/codeql-go-config.yml.
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == http.StatusNotFound {
		resp.Body.Close()
		return nil, errNotFound
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("HTTP %d from %s", resp.StatusCode, requestHost)
	}
	return resp.Body, nil
}

// canonicalUpdateHost returns the allowlist entry that matches host, and true
// if found. The returned string is a compile-time constant from allowedUpdateHosts,
// not derived from user input — which breaks the taint chain for SSRF analysis.
func canonicalUpdateHost(host string) (string, bool) {
	for _, allowed := range allowedUpdateHosts {
		if host == allowed {
			return allowed, true
		}
	}
	return "", false
}

// isAllowedUpdateHost reports whether host is in the update server allowlist.
func isAllowedUpdateHost(host string) bool {
	_, ok := canonicalUpdateHost(host)
	return ok
}

// checksumsFileName is the checksums file GoReleaser publishes with a release:
// quark_<version>_checksums.txt, the version without its leading "v".
func checksumsFileName(version string) string {
	return fmt.Sprintf("%s_%s_checksums.txt", binaryName, strings.TrimPrefix(version, "v"))
}

// verifyChecksumOf fetches the release checksums file at checksumsURL and
// checks its entry for archiveName against sum, the SHA-256 digest of the
// archive. It takes the digest rather than the archive so the caller can
// compute it while streaming to disk — the archive used to be held in memory
// purely to be hashed here (#1723).
//
// The file is sha256sum(1) output, one "<hex>  <filename>" line per archive.
// Anything short of a matching entry is an error: this is what stands between
// a download and the running binary.
func verifyChecksumOf(sum []byte, checksumsURL, archiveName string) error {
	checksums, err := fetchURL(checksumsURL)
	if err != nil {
		if errors.Is(err, errNotFound) {
			// Only *here* does a 404 mean "no checksum was published".
			return errChecksumUnavailable
		}
		return err
	}

	for _, line := range strings.Split(string(checksums), "\n") {
		fields := strings.Fields(line)
		if len(fields) != 2 || fields[1] != archiveName {
			continue
		}
		expected, err := hex.DecodeString(fields[0])
		if err != nil {
			return fmt.Errorf("invalid checksum for %s: %w", archiveName, err)
		}
		if !hmacEqual(sum, expected) {
			return fmt.Errorf("checksum mismatch for %s: expected %x, got %x", archiveName, expected, sum)
		}
		return nil
	}
	return fmt.Errorf("checksums file lists no entry for %s", archiveName)
}

// hmacEqual is a constant-time comparison of two byte slices.
func hmacEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := range a {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}

func isStaleBackupName(name string) bool {
	for _, prefix := range staleBackupPrefixes {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	return false
}

// replaceSelf streams the update archive from body onto disk and, once verify
// accepts what landed, extracts the binary and atomically replaces the running
// executable.
//
// verify receives the SHA-256 of the bytes written. Update always passes one;
// nil skips verification and exists for tests. Hashing happens as the archive streams to the temp
// file, so a 100 MB release never sits in memory — it used to be downloaded
// into a []byte purely so it could be hashed before this call (#1723).
// Extraction only begins after verify returns, so an archive that fails the
// check never reaches the executable.
func replaceSelf(body io.Reader, verify func(sum []byte) error) error {
	execPath, err := resolvedExecutable()
	if err != nil {
		return err
	}
	tmpFile, err := os.CreateTemp("", "quark_update_*")
	if err != nil {
		return fmt.Errorf("failed to create temp file for update: %w", err)
	}
	defer os.Remove(tmpFile.Name())
	defer tmpFile.Close()

	hash := sha256.New()
	if _, err := tmpFile.ReadFrom(io.TeeReader(body, hash)); err != nil {
		return fmt.Errorf("failed to write update to temp file: %w", err)
	}
	if err := tmpFile.Sync(); err != nil {
		return fmt.Errorf("failed to sync temp file: %w", err)
	}
	if verify != nil {
		if err := verify(hash.Sum(nil)); err != nil {
			return err
		}
	}
	// Rewind the temp file to the beginning
	if _, err := tmpFile.Seek(0, io.SeekStart); err != nil {
		return fmt.Errorf("failed to seek in temp file: %w", err)
	}

	gzReader, err := gzip.NewReader(tmpFile)
	if err != nil {
		return fmt.Errorf("failed to create gzip reader: %w", err)
	}
	defer gzReader.Close()

	tarReader := tar.NewReader(gzReader)
	var binFile *os.File
	for {
		header, err := tarReader.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("failed to read tar: %w", err)
		}
		if header.Typeflag == tar.TypeReg && (header.Name == binaryName || header.Name == fmt.Sprintf("./%s", binaryName)) {
			binFile, err = os.CreateTemp("", extractedName)
			if err != nil {
				return fmt.Errorf("failed to create temp file for extracted binary: %w", err)
			}
			if _, err := io.Copy(binFile, tarReader); err != nil {
				return fmt.Errorf("failed to extract binary from tar: %w", err)
			}
			if err := binFile.Sync(); err != nil {
				return fmt.Errorf("failed to sync extracted binary: %w", err)
			}
			break
		}
	}
	if binFile == nil {
		return errors.New("binary not found in archive")
	}
	defer os.Remove(binFile.Name())
	defer binFile.Close()

	// Make the extracted binary executable
	if err := os.Chmod(binFile.Name(), 0755); err != nil {
		return fmt.Errorf("failed to set executable permissions: %w", err)
	}

	// Close the file before operations
	binFile.Close()

	// Create a temporary file in the same directory as the target executable.
	// This keeps the subsequent rename atomic and on the same filesystem, so it
	// must not be relocated to /tmp — that would trade a permission failure for
	// a torn-binary failure. CanSelfUpdate checks this is writable up front.
	execDir := filepath.Dir(execPath)
	tmpNew, err := os.CreateTemp(execDir, ".quark_new_*")
	if err != nil {
		return fmt.Errorf(
			"%w: failed to create temp file in %s: %w",
			ErrSelfUpdateUnavailable, execDir, err,
		)
	}
	tmpNewPath := tmpNew.Name()
	defer os.Remove(tmpNewPath)

	// Copy the new binary to the target filesystem
	src, err := os.Open(binFile.Name())
	if err != nil {
		return fmt.Errorf("failed to open extracted binary: %w", err)
	}
	defer src.Close()

	if _, err := io.Copy(tmpNew, src); err != nil {
		tmpNew.Close()
		return fmt.Errorf("failed to copy new binary: %w", err)
	}

	if err := tmpNew.Sync(); err != nil {
		tmpNew.Close()
		return fmt.Errorf("failed to sync new binary: %w", err)
	}
	tmpNew.Close()

	// Set executable permissions on the new file
	if err := os.Chmod(tmpNewPath, 0755); err != nil {
		return fmt.Errorf("failed to set permissions on new binary: %w", err)
	}

	// Atomically rename the new binary over the old one
	// This works even while the old binary is running
	if err := os.Rename(tmpNewPath, execPath); err != nil {
		return fmt.Errorf("failed to replace executable: %w", err)
	}

	return nil
}

// selfUpdateDir returns the directory holding the running executable — the
// directory replaceSelf must be able to write to.
//
// Symlinks are resolved so that the answer is the directory the atomic rename
// actually lands in. With the binary installed at serviceBinaryPath and
// /usr/local/bin/quark kept as a symlink, the resolved directory is the
// group-writable one, not the root-owned one the symlink lives in.
func selfUpdateDir() (string, error) {
	execPath, err := resolvedExecutable()
	if err != nil {
		return "", err
	}
	return filepath.Dir(execPath), nil
}

// resolvedExecutable returns the path of the running binary with symlinks
// resolved, so the update lands on the real file rather than replacing a
// symlink with a regular file.
//
// On Linux os.Executable already resolves (/proc/self/exe); on darwin it can
// hand back the path as invoked. With /usr/local/bin/quark kept as a symlink
// into the self-updatable directory, that difference decides whether an update
// replaces the binary or clobbers the symlink.
func resolvedExecutable() (string, error) {
	execPath, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("failed to get executable path: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(execPath)
	if err != nil {
		// Keep the unresolved path: it is still the best available answer, and
		// the write probe decides whether it is usable.
		return execPath, nil
	}
	return resolved, nil
}

// canSelfUpdateIn is CanSelfUpdate against an explicit directory, so the
// failure path can be exercised without a binary installed in a directory it cannot write.
func canSelfUpdateIn(dir string) error {
	probe, err := os.CreateTemp(dir, ".quark_preflight_*")
	if err != nil {
		return fmt.Errorf(
			"%w: %s is not writable by %s.\n"+
				"Replacing a running binary in place requires write access to the directory "+
				"holding it.\n"+
				"Fix it by running `sudo quark install`, which moves the binary to %s and "+
				"leaves %s as a symlink to it, or update through your package manager or OS "+
				"image instead.\n"+
				"Underlying error: %w",
			ErrSelfUpdateUnavailable, dir, currentAccountDescription(),
			SelfUpdatableBinDir, LegacyBinPath, err,
		)
	}
	name := probe.Name()
	probe.Close()
	if err := os.Remove(name); err != nil {
		fmt.Printf("Warning: failed to remove preflight probe file %s: %v\n", name, err)
	}
	return nil
}

// currentAccountDescription names the account this process runs as, for error
// messages. os/user can fail in a static build with no cgo, so the numeric uid
// is the fallback — it is what `systemctl show quark -p User` will be compared
// against either way.
func currentAccountDescription() string {
	uid := os.Geteuid()
	if u, err := user.Current(); err == nil && u.Username != "" {
		return fmt.Sprintf("user %s (uid %d)", u.Username, uid)
	}
	return fmt.Sprintf("uid %d", uid)
}
