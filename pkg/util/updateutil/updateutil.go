// Package updateutil discovers, downloads, and installs quark releases from
// GitHub and Azure Blob Storage.
package updateutil

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"strings"
	"time"

	github "github.com/autobutler-org/quark/pkg/util/githubutil"
	"github.com/autobutler-org/quark/pkg/util/versionutil"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
)

type UpdateSourceKind string

const (
	UpdateSourceKindAzure  UpdateSourceKind = "azure"
	UpdateSourceKindGithub UpdateSourceKind = "github"
)

type UpdateSource struct {
	Kind    UpdateSourceKind `json:"kind"`
	Account string           `json:"account"`
	Path    string           `json:"path"`
	// BaseURLOverride replaces the computed base URL when set. Used in tests to
	// point requests at a mock HTTP server instead of github.com or Azure.
	BaseURLOverride string `json:"-"`
}

type UpdateVersion struct {
	Version string `json:"version"`
	URL     string `json:"url"`
}

// DefaultUpdateSources is the ordered list of places to look for releases.
// Every entry must actually publish assets named by ConstructArchiveName
// ("quark_<Os>_<arch>.tar.gz") — a source that cannot serve those only burns a
// round trip and buries the real failure inside a concatenated error string.
//
// autobutler-org/quark.org was removed here: no such repository exists. It was
// half-applied find-and-replace fallout from the AutoButler -> Quark rename
// (#1610). The nearby real repos are not substitutes — autobutler.org is the
// pre-rename repo, frozen at v0.12.0 and publishing "autobutler_*" assets that
// never match ConstructArchiveName, and quark.autobutler.org is the website and
// publishes no releases at all.
var DefaultUpdateSources = []*UpdateSource{
	NewUpdateSource(
		UpdateSourceKindAzure,
		"quarkrelease",
		"releases/quark",
	),
	NewUpdateSource(
		UpdateSourceKindGithub,
		"autobutler-org",
		"quark",
	),
}

var client *azblob.Client

func ConstructArchiveName() string {
	goos := fmt.Sprintf("%s%s", strings.ToUpper(string(runtime.GOOS[0])), string(runtime.GOOS[1:]))
	return fmt.Sprintf("quark_%s_%s.tar.gz", goos, runtime.GOARCH)
}

func GetLatestVersionFromDefaultSources() (string, error) {
	for _, source := range DefaultUpdateSources {
		version, err := GetLatestVersion(source)
		if err != nil {
			continue
		}
		return version, nil
	}
	return "", errors.New("failed to get latest version from all default sources")
}

func GetLatestVersion(source *UpdateSource) (string, error) {
	if source == nil {
		return GetLatestVersionFromDefaultSources()
	}
	switch source.Kind {
	case UpdateSourceKindGithub:
		org, repo := source.Account, source.Path
		release, err := github.FetchLatestRelease(org, repo)
		if err != nil {
			return "", fmt.Errorf("failed to fetch releases: %w", err)
		}

		url := getAssetURLFromRelease(release)
		if url == "" {
			return "", errors.New("no suitable asset found in latest release")
		}

		return release.TagName, nil
	case UpdateSourceKindAzure:
		releases, err := ListPossibleUpdates(source, true)
		if err != nil {
			return "", fmt.Errorf("failed to list releases: %w", err)
		}
		if len(releases.Versions) == 0 {
			return "", errors.New("no releases found in Azure source")
		}
		// Sort by semver and return the highest. Lexicographic order is not
		// reliable for semver (e.g. "v0.9.0" > "v0.16.0" lexicographically).
		latest := releases.Versions[0]
		for _, v := range releases.Versions[1:] {
			if versionutil.CompareVersions(
				versionutil.Version{Semver: v.Version},
				versionutil.Version{Semver: latest.Version},
			) == 1 {
				latest = v
			}
		}
		return latest.Version, nil
	default:
		return "", fmt.Errorf("unsupported update source kind: %s", source.Kind)
	}
}

func IsDevelopmentVersion(version string) bool {
	if matched, err := regexp.MatchString("^.*-", version); err != nil || matched {
		return true
	}
	if matched, err := regexp.MatchString("-.*$", version); err != nil || matched {
		return true
	}
	return false
}

// ListPossibleUpdatesResult contains the result of listing possible updates
type ListPossibleUpdatesResult struct {
	Versions []*UpdateVersion
}

// ListPossibleUpdatesFromDefaultSources lists possible updates from all default sources
func ListPossibleUpdatesFromDefaultSources(allVersions bool) (*ListPossibleUpdatesResult, error) {
	for _, source := range DefaultUpdateSources {
		result, err := ListPossibleUpdates(source, allVersions)
		if err != nil {
			continue
		}
		return result, nil
	}
	return nil, errors.New("failed to list updates from all default sources")
}

// ListPossibleUpdates retrieves all available releases that are newer than the current version
func ListPossibleUpdates(source *UpdateSource, allVersions bool) (*ListPossibleUpdatesResult, error) {
	if source == nil {
		return ListPossibleUpdatesFromDefaultSources(allVersions)
	}

	updateReleases := []*UpdateVersion{}
	switch source.Kind {
	case UpdateSourceKindGithub:
		org, repo := source.Account, source.Path
		releases, err := github.FetchReleases(org, repo)
		if err != nil {
			return nil, fmt.Errorf("failed to fetch releases: %w", err)
		}
		for _, release := range releases {
			url := getAssetURLFromRelease(release)
			if url == "" {
				continue
			}
			updateReleases = append(updateReleases, &UpdateVersion{
				Version: release.TagName,
				URL:     url,
			})
		}
	case UpdateSourceKindAzure:
		prefix := source.BlobPrefix()
		pager := client.NewListBlobsFlatPager(
			source.Container(),
			&azblob.ListBlobsFlatOptions{
				Prefix: prefix,
			},
		)

		for pager.More() {
			resp, err := pager.NextPage(context.Background())
			if err != nil {
				return nil, fmt.Errorf("failed to list blobs: %w", err)
			}

			for _, blob := range resp.Segment.BlobItems {
				trimmed := strings.TrimPrefix(*blob.Name, *prefix)
				split := strings.Split(trimmed, "/")
				version, artifact := split[0], split[1]
				if strings.HasSuffix(artifact, ".txt") {
					continue
				}
				if !strings.Contains(artifact, ConstructArchiveName()) {
					continue
				}
				updateReleases = append(updateReleases, &UpdateVersion{
					Version: version,
					URL:     fmt.Sprintf("%s/%s/%s", source.BaseUrl(), source.Container(), *blob.Name),
				})
			}
		}
		slices.Reverse(updateReleases)
	default:
		return nil, fmt.Errorf("unsupported update source kind: %s", source.Kind)
	}

	if allVersions {
		return &ListPossibleUpdatesResult{
			Versions: updateReleases,
		}, nil
	}

	currentVersion := versionutil.GetVersion()
	if currentVersion.Semver == "" {
		return &ListPossibleUpdatesResult{
			Versions: updateReleases,
		}, nil
	}

	possibleUpdates := make([]*UpdateVersion, 0)
	for _, release := range updateReleases {
		if IsDevelopmentVersion(release.Version) {
			continue
		}
		comparison := versionutil.CompareVersions(
			versionutil.Version{
				Semver: release.Version,
			},
			*currentVersion,
		)
		if comparison > 0 {
			possibleUpdates = append(possibleUpdates, release)
		}
	}

	return &ListPossibleUpdatesResult{
		Versions: possibleUpdates,
	}, nil
}

// UpdateFromDefaultSources tries to update from all default sources until one succeeds
func UpdateFromDefaultSources(version string) error {
	// Checked once, before the loop. Without this the updater downloaded and
	// extracted the whole binary once per source before discovering it could
	// not write the result anywhere (#1609).
	if err := CanSelfUpdate(); err != nil {
		return err
	}

	errs := []error{}
	for _, source := range DefaultUpdateSources {
		fmt.Printf("Attempting to update from source: %v, with URL %s\n", source, source.UpdateUrl())
		err := Update(source, version)
		if err != nil {
			errs = append(errs, fmt.Errorf("failed to update from source %v: %w", source, err))
			continue
		}
		return nil
	}
	return fmt.Errorf("failed to update from all default sources: %v", errs)
}

// Update downloads and installs a new version of the application. The archive
// is verified against the checksums file the release publishes beside it, on
// the same source, before the running binary is replaced. Verification is
// required: a missing checksums file, a missing entry or a mismatch all stop
// the update.
func Update(source *UpdateSource, version string) error {
	if source == nil {
		return UpdateFromDefaultSources(version)
	}

	if version == "" {
		return errors.New("version cannot be empty")
	}

	// Before the download, not after: it is wasted work if the binary cannot
	// be replaced at the end of it (#1609).
	if err := CanSelfUpdate(); err != nil {
		return err
	}

	baseUrl := source.UpdateUrl()
	if baseUrl == "" {
		return fmt.Errorf("invalid update source: %s", source.Kind)
	}

	archiveName := ConstructArchiveName()
	url := fmt.Sprintf("%s/%s/%s", baseUrl, version, archiveName)
	fmt.Println("Downloading update from", url)

	// Stream the archive to disk rather than into memory: self-update runs on
	// the device, and holding a whole release in a []byte is the last thing a
	// low-memory box needs (#1723). replaceSelf hashes what it writes, and the
	// checksum is verified before anything is extracted.
	body, err := fetchStream(url)
	if err != nil {
		if errors.Is(err, errNotFound) {
			return fmt.Errorf(
				"no release asset %s for version %s at %s: the version, the release, "+
					"or the update source itself does not exist: %w",
				archiveName, version, source, err,
			)
		}
		return fmt.Errorf("failed to download update from %s: %w", url, err)
	}
	defer body.Close()

	// GoReleaser publishes one checksums file per release, not a .sha256 per
	// archive. Every release with a quark_<Os>_<arch> archive has one, on both
	// sources, so there is no release this fails closed on.
	checksumsURL := fmt.Sprintf("%s/%s/%s", baseUrl, version, checksumsFileName(version))
	verify := func(sum []byte) error {
		if err := verifyChecksumOf(sum, checksumsURL, archiveName); err != nil {
			return fmt.Errorf("checksum verification against %s failed: %w", checksumsURL, err)
		}
		return nil
	}

	if err := replaceSelf(body, verify); err != nil {
		return fmt.Errorf("failed to replace self with update from %s: %w", url, err)
	}

	fmt.Println("Update successful.")
	return nil
}

// errNotFound is returned by fetchURL on HTTP 404. It carries no opinion about
// what was missing — callers wrap it with the meaning for their own request.
// It used to be spelled errChecksumUnavailable and returned for *every* 404,
// so a download from a repository that does not exist reported "checksum file
// not found" and sent readers looking at release assets (#1610).
var errNotFound = errors.New("not found (HTTP 404)")

// errChecksumUnavailable means the archive downloaded fine but the release's
// checksums file was not found beside it.
var errChecksumUnavailable = errors.New("checksum file not found")

// allowHTTPInFetchURL relaxes the HTTPS-only restriction in fetchURL.
// It must only be set to true in tests.
var allowHTTPInFetchURL bool

// allowedUpdateHosts is the set of domains the update client may contact.
// All others are rejected to prevent SSRF via a compromised or hijacked update source.
var allowedUpdateHosts = []string{
	"github.com",
	"objects.githubusercontent.com",
	"quarkrelease.blob.core.windows.net",
	// Added at test time via allowHTTPInFetchURL + local httptest servers
}

const binaryName = "quark"

var extractedName = fmt.Sprintf("%s_extracted", binaryName)

var staleBackupPrefixes = []string{"autobutler_backup", "quark_backup"}

type RemoveStaleBackupsParams struct {
	Dir string
}

type RemoveStaleBackupsResult struct {
	Removed []string
}

func RemoveStaleBackups(params RemoveStaleBackupsParams) (RemoveStaleBackupsResult, error) {
	dir := params.Dir
	if dir == "" {
		dir = os.TempDir()
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return RemoveStaleBackupsResult{}, fmt.Errorf("failed to read %s: %w", dir, err)
	}
	result := RemoveStaleBackupsResult{}
	var errs []error
	for _, entry := range entries {
		if !entry.Type().IsRegular() || !isStaleBackupName(entry.Name()) {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		if err := os.Remove(path); err != nil {
			errs = append(errs, err)
			continue
		}
		result.Removed = append(result.Removed, path)
	}
	return result, errors.Join(errs...)
}

// ── Self-update preflight (#1609) ───────────────────────────────────────────

// ErrSelfUpdateUnavailable reports that this process cannot replace its own
// binary, whatever the update source. Callers should surface it as-is: the
// wrapped message names the directory, the account, and the way out.
var ErrSelfUpdateUnavailable = errors.New("cannot self-update")

// CanSelfUpdate reports whether the running process can replace its own binary
// in place, without downloading anything.
//
// replaceSelf creates its temp file in the directory holding the executable so
// the final rename is atomic and on the same filesystem — that is correct and
// must not be traded for a temp file in /tmp. The consequence is that the
// account the service runs as needs write access to that directory. Under the
// packaged systemd unit it did not, so every update attempt downloaded and
// extracted the full binary once per source before failing on a raw
// "permission denied" from deep inside the updater (#1609).
//
// The check is a real create-and-remove rather than a permission-bit test, so
// it agrees with what replaceSelf will actually be allowed to do — read-only
// mounts, ACLs and immutable flags included.
func CanSelfUpdate() error {
	dir, err := selfUpdateDir()
	if err != nil {
		return fmt.Errorf("%w: %w", ErrSelfUpdateUnavailable, err)
	}
	return canSelfUpdateIn(dir)
}

// SelfUpdatableBinDir and LegacyBinPath describe the install layout that makes
// self-update possible. They live here rather than in internal/install so the
// preflight message can name the fix; internal/install is what implements it.
const (
	SelfUpdatableBinDir = "/opt/quark/bin"
	LegacyBinPath       = "/usr/local/bin/quark"
)

// ExitForRestart exits the process after a short pause, so the process manager
// (systemd's Restart=always, or launchd) starts Quark again. The pause lets the
// HTTP response that asked for the restart reach the client first, so call it
// in a goroutine and return the response.
func ExitForRestart() {
	fmt.Println("Exiting to allow process manager (launchctl/systemd) to restart...")
	time.Sleep(2 * time.Second)
	os.Exit(0)
}
