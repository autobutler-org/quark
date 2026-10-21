package fileutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/docreadutil"
	"github.com/autobutler-org/quark/pkg/util/officezip"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// MaxDocumentPartBytes bounds one image served out of a document, the same
// bound pptxutil puts on an imported picture.
const MaxDocumentPartBytes = 100 << 20 // 100 MiB

// PreviewDocumentParams says which document to preview and where the block
// stream goes.
type PreviewDocumentParams struct {
	// Ctx ends the preview early when it is done.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// FilePath is the files-relative path of the document.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Out receives the NDJSON block stream. Nothing is written to it until
	// the document has opened, so a file that cannot be previewed fails
	// before the first byte.
	Out io.Writer
}

// PreviewDocumentResult reports what a preview wrote.
type PreviewDocumentResult struct {
	// Truncated reports that a limit stopped the stream before the
	// document's end.
	Truncated bool
}

// PreviewDocument streams a word-processing document as the NDJSON block
// stream the document viewer draws (docs/architecture/read-only-documents.md,
// Decision 2). The document is read in place and each block is written as it
// is read. A failure before output begins is a [NotFoundError] or an
// [UnsupportedError]; one after it leaves the stream without its end line,
// which is how the client tells a cut-off stream from a whole one.
func PreviewDocument(params PreviewDocumentParams) (PreviewDocumentResult, error) {
	format, ok := docreadutil.FormatForName(params.FilePath)
	if !ok {
		return PreviewDocumentResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a document Quark can show: %s", filepath.Base(params.FilePath)),
		}
	}
	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return PreviewDocumentResult{}, err
	}
	source, size, closer, err := openZip(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return PreviewDocumentResult{}, err
	}
	defer closer.Close()

	result, err := docreadutil.Convert(docreadutil.ConvertParams{
		Ctx:    params.Ctx,
		Source: source,
		Size:   size,
		Format: format,
		Output: docreadutil.OutputNDJSON,
		Out:    params.Out,
	})
	if err != nil {
		return PreviewDocumentResult{}, documentError(err)
	}
	return PreviewDocumentResult{Truncated: result.Truncated}, nil
}

// OpenDocumentPartParams names one image inside a document.
type OpenDocumentPartParams struct {
	// Ctx bounds opening the document.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// FilePath is the files-relative path of the document.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// Part is the image's entry name inside the document, as an image
	// block names it: "word/media/image1.png".
	Part string
}

// OpenDocumentPartResult is an opened image part.
type OpenDocumentPartResult struct {
	// Reader streams the image, failing once it passes
	// [MaxDocumentPartBytes] whatever size the entry declares.
	Reader io.Reader
	// ContentType is the image's media type, from its extension.
	ContentType string
	// Close closes the part and the document it is read from.
	Close func() error
}

// OpenDocumentPart opens one image inside a document for streaming. It is
// not a general zip browser: only an entry under the format's media folder,
// named without any climbing, with an image extension the client decodes,
// and present in the document's directory, is served. Anything else is a
// [NotFoundError].
func OpenDocumentPart(params OpenDocumentPartParams) (OpenDocumentPartResult, error) {
	mediaDir, ok := documentMediaDir(params.FilePath)
	if !ok {
		return OpenDocumentPartResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a document Quark can show: %s", filepath.Base(params.FilePath)),
		}
	}
	contentType, ok := documentPartContentType(mediaDir, params.Part)
	if !ok {
		return OpenDocumentPartResult{}, notFoundf("no image %q in the document", params.Part)
	}
	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return OpenDocumentPartResult{}, err
	}
	source, size, closer, err := openZip(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return OpenDocumentPartResult{}, err
	}
	pkg, err := officezip.Open(source, size, officezip.Limits{
		MaxPartBytes:  MaxDocumentPartBytes,
		MaxTotalBytes: MaxDocumentPartBytes,
	})
	if err != nil {
		closer.Close()
		return OpenDocumentPartResult{}, documentError(err)
	}
	part, err := pkg.Part(params.Part)
	if err != nil {
		closer.Close()
		if errors.Is(err, officezip.ErrMissingPart) {
			return OpenDocumentPartResult{}, notFoundf("no image %q in the document", params.Part)
		}
		return OpenDocumentPartResult{}, documentError(err)
	}
	return OpenDocumentPartResult{
		Reader:      part,
		ContentType: contentType,
		Close: func() error {
			return errors.Join(part.Close(), closer.Close())
		},
	}, nil
}

// documentMediaDir is the media folder, lowercased, of the document
// filePath names: the one folder the part endpoint serves images from. It is
// "" for a format with no folder of its own, and not ok for a file that is
// not a document Quark can show. Each format's media folder joins here as
// its reader lands.
func documentMediaDir(filePath string) (string, bool) {
	if IsPptxPath(filePath) {
		return "ppt/media/", true
	}
	format, ok := docreadutil.FormatForName(filePath)
	if !ok {
		return "", false
	}
	switch format {
	case docreadutil.FormatDOCX, docreadutil.FormatDOCM:
		return "word/media/", true
	case docreadutil.FormatODT:
		// Matched lowercased; ODF writes Pictures/.
		return "pictures/", true
	}
	return "", true
}

// documentPartContentType reports whether part names an image the part
// endpoint may serve from a document whose media folder is mediaDir, and its
// media type: an entry under that folder, already in clean form, with an
// extension the client decodes.
func documentPartContentType(mediaDir, part string) (string, bool) {
	lower := strings.ToLower(part)
	if mediaDir == "" || part == "" || strings.ContainsAny(part, "\\\x00") || path.Clean(part) != part ||
		strings.Contains(part, "..") || !strings.HasPrefix(lower, mediaDir) || len(lower) == len(mediaDir) {
		return "", false
	}
	switch path.Ext(lower) {
	case ".png":
		return "image/png", true
	case ".jpg", ".jpeg":
		return "image/jpeg", true
	case ".gif":
		return "image/gif", true
	case ".webp":
		return "image/webp", true
	case ".bmp":
		return "image/bmp", true
	}
	return "", false
}
