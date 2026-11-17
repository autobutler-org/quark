package photoutil

import (
	"path"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

const documentMediaMarkerName = "embedded-document-media"

func documentMediaMarker(dir string) string {
	return path.Join(dir, storageutil.TrashPathPrefix, documentMediaMarkerName)
}
