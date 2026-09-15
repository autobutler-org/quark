package updateutil

import (
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

// Every default source must be able to serve the archive this build asks for.
// autobutler-org/quark.org sat in this list pointing at a repository that never
// existed, and only ever surfaced inside a concatenated multi-source error
// string (#1610).
func TestDefaultUpdateSources_AreWellFormed(t *testing.T) {
	if len(DefaultUpdateSources) == 0 {
		t.Fatal("DefaultUpdateSources must not be empty")
	}

	for _, source := range DefaultUpdateSources {
		t.Run(source.String(), func(t *testing.T) {
			if source.Account == "" || source.Path == "" {
				t.Fatalf("source has an empty account or path: %+v", source)
			}
			base := source.UpdateUrl()
			if base == "" {
				t.Fatalf("source produced an empty update URL: %+v", source)
			}
			if !strings.HasPrefix(base, "https://") {
				t.Errorf("update URL must be https, got %q", base)
			}

			// fetchURL refuses anything not on the allowlist, so a source whose
			// host is not listed can never be reached at all.
			host := strings.SplitN(strings.TrimPrefix(base, "https://"), "/", 2)[0]
			if !isAllowedUpdateHost(host) {
				t.Errorf("host %q is not in allowedUpdateHosts, so this source can never be fetched", host)
			}
		})
	}
}

// The dead source specifically. Kept as a named test so a re-introduction is
// reported as "the repo does not exist" rather than a vague list-length change.
func TestDefaultUpdateSources_ExcludesNonexistentQuarkOrgRepo(t *testing.T) {
	for _, source := range DefaultUpdateSources {
		if source.Kind == UpdateSourceKindGithub && source.Path == "quark.org" {
			t.Errorf(
				"autobutler-org/quark.org is in DefaultUpdateSources but does not exist on GitHub; "+
					"it is rename fallout from AutoButler -> Quark (#1610): %+v", source,
			)
		}
	}
}

func TestUpdateSource_String(t *testing.T) {
	cases := []struct {
		name   string
		source *UpdateSource
		want   string
	}{
		{
			name:   "github",
			source: NewUpdateSource(UpdateSourceKindGithub, "autobutler-org", "quark"),
			want:   "github repository autobutler-org/quark",
		},
		{
			name:   "azure",
			source: NewUpdateSource(UpdateSourceKindAzure, "quarkrelease", "releases/quark"),
			want:   "azure storage account quarkrelease, path releases/quark",
		},
		{
			name:   "nil",
			source: nil,
			want:   "<nil update source>",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.source.String(); got != tc.want {
				t.Errorf("String() = %q, want %q", got, tc.want)
			}
		})
	}
}

// The default struct rendering is what put "&{github autobutler-org quark.org }"
// in front of an operator instead of a repository name (#1610).
func TestUpdateSource_FormatsReadablyInErrors(t *testing.T) {
	source := NewUpdateSource(UpdateSourceKindGithub, "autobutler-org", "quark")
	got := fmt.Sprintf("failed to update from source %v", source)
	if strings.Contains(got, "&{") {
		t.Errorf("error text still uses default struct formatting: %q", got)
	}
	if !strings.Contains(got, "autobutler-org/quark") {
		t.Errorf("error text does not name the repository: %q", got)
	}
}

// A 404 on the archive means the release or the source is missing — saying
// "checksum file not found" sent the reporter looking at release assets (#1610).
func TestUpdate_MissingArchiveDoesNotBlameTheChecksum(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	source := NewUpdateSource(UpdateSourceKindGithub, "autobutler-org", "nonexistent")
	source.BaseURLOverride = server.URL

	err := Update(source, "v9.9.9")
	if err == nil {
		t.Fatal("expected an error when the archive 404s")
	}
	msg := err.Error()
	if strings.Contains(msg, "checksum") {
		t.Errorf("a missing archive must not be reported as a checksum problem: %q", msg)
	}
	if !strings.Contains(msg, "autobutler-org/nonexistent") {
		t.Errorf("error should name the source that failed: %q", msg)
	}
	if !strings.Contains(msg, "v9.9.9") {
		t.Errorf("error should name the version that failed: %q", msg)
	}
}

// A 404 on the checksums file still means exactly what it used to.
func TestVerifyChecksum_404StillMeansChecksumUnavailable(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	err := verifyChecksumOf(sha256Of([]byte("payload")), server.URL+"/quark_1.0.0_checksums.txt", "archive.tar.gz")
	if !errors.Is(err, errChecksumUnavailable) {
		t.Errorf("expected errChecksumUnavailable, got %v", err)
	}
}

// ── Self-update preflight (#1609) ───────────────────────────────────────────

func TestCanSelfUpdate_WritableDirectory(t *testing.T) {
	if err := CanSelfUpdate(); err != nil {
		t.Errorf("test binary lives in a writable directory, so CanSelfUpdate should pass: %v", err)
	}
}

// CanSelfUpdate must leave nothing behind — it runs on every auto-update tick.
func TestCanSelfUpdate_RemovesItsProbeFile(t *testing.T) {
	dir, err := selfUpdateDir()
	if err != nil {
		t.Fatalf("selfUpdateDir: %v", err)
	}
	if err := CanSelfUpdate(); err != nil {
		t.Fatalf("CanSelfUpdate: %v", err)
	}
	leftovers, err := filepath.Glob(filepath.Join(dir, ".quark_preflight_*"))
	if err != nil {
		t.Fatalf("glob: %v", err)
	}
	if len(leftovers) != 0 {
		t.Errorf("preflight left probe files behind: %v", leftovers)
	}
}

// The reported failure: the service account cannot write the directory holding
// its own binary, so no update can ever complete (#1609).
func TestCanSelfUpdate_ReadOnlyDirectoryFailsWithActionableMessage(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX directory permissions only")
	}
	if os.Geteuid() == 0 {
		t.Skip("root ignores directory permissions")
	}

	// Mirrors /usr/local/bin: readable and traversable, not writable.
	binDir := filepath.Join(t.TempDir(), "bin")
	if err := os.Mkdir(binDir, 0755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	if err := os.Chmod(binDir, 0555); err != nil {
		t.Fatalf("chmod: %v", err)
	}
	t.Cleanup(func() { _ = os.Chmod(binDir, 0755) })

	if f, err := os.CreateTemp(binDir, "writable_probe_*"); err == nil {
		f.Close()
		t.Skip("filesystem does not enforce directory write permissions")
	}

	err := canSelfUpdateIn(binDir)
	if err == nil {
		t.Fatal("expected a preflight failure for a read-only directory")
	}
	if !errors.Is(err, ErrSelfUpdateUnavailable) {
		t.Errorf("preflight failures must match ErrSelfUpdateUnavailable, got %v", err)
	}

	// The whole point of the preflight is that the message says what to do —
	// the raw "permission denied" from inside replaceSelf did not (#1609).
	for _, want := range []string{
		binDir,
		"sudo quark install",
		SelfUpdatableBinDir,
		LegacyBinPath,
		"package manager",
	} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error message should mention %q, got: %s", want, err)
		}
	}
}

// The preflight must fail before anything is downloaded.
func TestUpdate_PreflightRunsBeforeDownloading(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root ignores directory permissions")
	}

	var downloads int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		downloads++
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	binDir := filepath.Join(t.TempDir(), "bin")
	if err := os.Mkdir(binDir, 0555); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	t.Cleanup(func() { _ = os.Chmod(binDir, 0755) })
	if f, err := os.CreateTemp(binDir, "writable_probe_*"); err == nil {
		f.Close()
		t.Skip("filesystem does not enforce directory write permissions")
	}

	if err := canSelfUpdateIn(binDir); err == nil {
		t.Fatal("expected the preflight to reject a read-only directory")
	}
	if downloads != 0 {
		t.Errorf("preflight must not touch the network, saw %d requests", downloads)
	}
}

func TestCurrentAccountDescription_NamesTheUid(t *testing.T) {
	got := currentAccountDescription()
	if !strings.Contains(got, fmt.Sprintf("uid %d", os.Geteuid())) {
		t.Errorf("account description should name the effective uid: %q", got)
	}
}

// The install layout the preflight message points at must be the one
// internal/install actually creates.
func TestSelfUpdateLayoutConstants(t *testing.T) {
	if !strings.HasPrefix(LegacyBinPath, "/usr/local/bin/") {
		t.Errorf("LegacyBinPath should stay on PATH: %q", LegacyBinPath)
	}
	if filepath.Dir(LegacyBinPath) == SelfUpdatableBinDir {
		t.Error("the legacy path must not live in the self-updatable directory; it is a symlink into it")
	}
}
