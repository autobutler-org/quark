package updateutil

import (
	"fmt"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/githubutil"
)

// NewUpdateSource creates a new UpdateSource with the specified kind, account, and path
func NewUpdateSource(kind UpdateSourceKind, account string, path string) *UpdateSource {
	return &UpdateSource{
		Kind:    kind,
		Account: account,
		Path:    path,
	}
}

// String renders a source the way an operator needs to read it in an error.
// The default struct formatting produced "&{github autobutler-org quark.org }",
// which is where a 404 on a nonexistent repository went to hide (#1610).
func (s *UpdateSource) String() string {
	if s == nil {
		return "<nil update source>"
	}
	switch s.Kind {
	case UpdateSourceKindGithub:
		return fmt.Sprintf("github repository %s/%s", s.Account, s.Path)
	case UpdateSourceKindAzure:
		return fmt.Sprintf("azure storage account %s, path %s", s.Account, s.Path)
	default:
		return fmt.Sprintf("unknown source kind %q (%s/%s)", s.Kind, s.Account, s.Path)
	}
}

func (s *UpdateSource) BaseUrl() string {
	if s.BaseURLOverride != "" {
		return s.BaseURLOverride
	}
	switch s.Kind {
	case UpdateSourceKindGithub:
		return fmt.Sprintf("https://github.com/%s/%s/releases/download", s.Account, s.Path)
	case UpdateSourceKindAzure:
		return fmt.Sprintf("https://%s.blob.core.windows.net", s.Account)
	default:
		return ""
	}
}

func (s *UpdateSource) UpdateUrl() string {
	switch s.Kind {
	case UpdateSourceKindGithub:
		// BaseUrl() already includes /releases/download for GitHub sources.
		return s.BaseUrl()
	case UpdateSourceKindAzure:
		return fmt.Sprintf("%s/%s", s.BaseUrl(), s.Path)
	default:
		return ""
	}
}

func (s *UpdateSource) Container() string {
	if s.Kind == UpdateSourceKindAzure {
		return strings.Split(s.Path, "/")[0]
	}
	return ""
}

func (s *UpdateSource) BlobPrefix() *string {
	if s.Kind == UpdateSourceKindAzure {
		parts := strings.Split(s.Path, "/")
		if len(parts) > 1 {
			prefix := strings.Join(parts[1:], "/") + "/"
			return &prefix
		}
	}
	return nil
}

func getAssetURLFromRelease(release *githubutil.Release, archiveName string) string {
	for _, asset := range release.Assets {
		if strings.HasSuffix(asset.BrowserDownloadURL, archiveName) {
			return asset.BrowserDownloadURL
		}
	}
	return ""
}
