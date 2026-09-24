package uploadutil

import (
	"log/slog"
	"mime/multipart"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/derivativeutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"
)

// Attach stores a sidecar part for the most recent file written under the
// name it carries. A part that is not a sidecar, names no file written before
// it, or does not hold a valid JPEG is skipped: the file it came with has
// landed, and it only goes without a client-rendered thumbnail, the same as
// from an older client that sends none.
func (s Sidecars) Attach(part *multipart.Part, written []storageutil.UploadedFile) {
	kind, ok := derivativeutil.ParseKind(part.FormName())
	if !ok {
		return
	}
	name := filepath.Base(part.FileName())
	for i := len(written) - 1; i >= 0; i-- {
		if written[i].SourceName != name {
			continue
		}
		if err := s.store(part, kind, written[i].Path); err != nil {
			slog.Warn("upload: skipped a sidecar", "kind", kind, "file", written[i].Path, "err", err)
		}
		return
	}
	slog.Warn("upload: skipped a sidecar for a file not uploaded before it", "kind", kind, "name", name)
}

func (s Sidecars) store(part *multipart.Part, kind derivativeutil.Kind, relPath string) error {
	fileType := storageutil.DetermineFileTypeFromPath(relPath)
	if fileType != storageutil.FileTypeImage && fileType != storageutil.FileTypeVideo {
		return thumbnailutil.ErrNotMedia
	}
	// The photo tables key a path with no leading slash.
	relPath = strings.TrimPrefix(filepath.ToSlash(relPath), "/")
	resolved, err := s.Storage.ResolvePath(storageutil.ResolvePathParams{RelPath: relPath, Serial: s.Serial})
	if err != nil {
		return err
	}
	var queries *db.Queries
	if s.Database != nil {
		queries = s.Database.Queries
	}
	_, err = thumbnailutil.StoreDerivative(thumbnailutil.StoreDerivativeParams{
		Queries:    queries,
		Serial:     s.Serial,
		RelPath:    relPath,
		SourcePath: resolved.FullPath,
		Kind:       kind,
		Reader:     part,
		IsVideo:    fileType == storageutil.FileTypeVideo,
	})
	return err
}
