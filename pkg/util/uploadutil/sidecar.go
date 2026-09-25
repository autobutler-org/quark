package uploadutil

import (
	"log/slog"
	"mime/multipart"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/thumbnailutil"
)

// Attach stores a "thumbnail" part for the most recent file written under the
// name it carries. A part that is not a thumbnail, names no file written
// before it, belongs to a file that is not a photo or video, or does not hold
// a valid JPEG is skipped: the file it came with has landed, and it only goes
// without a client-rendered thumbnail, the same as from an older client.
func (s Sidecars) Attach(part *multipart.Part, written []storageutil.UploadedFile) {
	if part.FormName() != "thumbnail" {
		return
	}
	name := filepath.Base(part.FileName())
	for i := len(written) - 1; i >= 0; i-- {
		if written[i].SourceName != name {
			continue
		}
		if err := s.store(part, written[i].Path); err != nil {
			slog.Warn("upload: skipped a thumbnail", "file", written[i].Path, "err", err)
		}
		return
	}
	slog.Warn("upload: skipped a thumbnail for a file not uploaded before it", "name", name)
}

func (s Sidecars) store(part *multipart.Part, relPath string) error {
	fileType := storageutil.DetermineFileTypeFromPath(relPath)
	if fileType != storageutil.FileTypeImage && fileType != storageutil.FileTypeVideo {
		return thumbnailutil.ErrNotMedia
	}
	var queries *db.Queries
	if s.Database != nil {
		queries = s.Database.Queries
	}
	_, err := thumbnailutil.StoreClientThumbnail(thumbnailutil.StoreClientThumbnailParams{
		Queries: queries,
		Serial:  s.Serial,
		RelPath: relPath,
		Reader:  part,
		IsVideo: fileType == storageutil.FileTypeVideo,
	})
	return err
}
