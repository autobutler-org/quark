package fileutil

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"path"
	"path/filepath"
	"strings"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/pptxutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ImportPptxParams imports one PowerPoint file as a .qslide the Slides editor
// opens.
type ImportPptxParams struct {
	// Ctx bounds the read and the writes.
	Ctx context.Context
	// Registry reads and writes through the VFS when no serial routes past it.
	Registry vfs.Registry
	// Storage serves the request for a device-scoped path, or when there is
	// no VFS namespace to route to.
	Storage *storageutil.StorageService
	// EventBus is told about the files that appeared. Required, as it is for
	// every other mutation here.
	EventBus *eventbus.Bus
	// FilePath is the files-relative path of the .pptx.
	FilePath string
	// RootDir is the folder the .qslide is written into, files-relative; ""
	// is the files root.
	RootDir string
	// Serial identifies the device, empty for the internal one. The .pptx is
	// read from it and the presentation written to it.
	Serial string
}

// ImportPptxResult reports the .qslide that was written.
type ImportPptxResult struct {
	// Path is where the presentation landed, files-relative. A name already
	// taken is kept, and the import lands beside it as Talk_(1).qslide.
	Path string
	// MediaDir is the folder its pictures were stored in, "" when it has
	// none.
	MediaDir string
	// MediaDirCreated is true when the import created MediaDir.
	MediaDirCreated bool
	// Media lists the pictures stored, files-relative.
	Media []string
	// Slides and Pictures are what the presentation came to.
	Slides   int
	Pictures int
	// Warnings lists what was left out or approximated, slide by slide.
	Warnings []pptxutil.ImportWarning
}

// ImportPptxToQslide reads the PowerPoint file at params.FilePath and writes
// it as a .qslide in params.RootDir, named after it (#1171). Its pictures are
// copied into a <name>_media folder beside the presentation, which names them
// by those paths. The .pptx itself is left untouched.
//
// Nothing is written over: the presentation and each picture land under a
// free numbered name when theirs is taken, as an upload that keeps both does.
// The import streams: the package is read in place, each picture is copied
// straight from the archive, and the .qslide is piped into its file a slide
// at a time. A package that fails partway leaves nothing behind.
func ImportPptxToQslide(params ImportPptxParams) (ImportPptxResult, error) {
	if !IsPptxPath(params.FilePath) {
		return ImportPptxResult{}, &UnsupportedError{
			Err: fmt.Errorf("not a PowerPoint file Quark can import: %s", filepath.Base(params.FilePath)),
		}
	}
	if climbsOut(params.RootDir) {
		return ImportPptxResult{}, invalidPath(params.RootDir)
	}
	rootDir := cleanRelPath(params.RootDir)
	if rootDir == "." {
		rootDir = ""
	}
	base := path.Base(cleanRelPath(params.FilePath))
	stem := strings.TrimSuffix(base, filepath.Ext(base))
	mediaDir := path.Join(rootDir, stem+"_media")
	mediaDirExisted, err := fileExists(params.Ctx, params.Registry, params.Storage, params.Serial, mediaDir)
	if err != nil {
		return ImportPptxResult{}, err
	}

	source, size, closer, err := openXlsxSource(ConvertXlsxParams{
		Ctx:      params.Ctx,
		Registry: params.Registry,
		Storage:  params.Storage,
		FilePath: params.FilePath,
		Serial:   params.Serial,
	})
	if err != nil {
		return ImportPptxResult{}, err
	}
	defer closer.Close()

	// Each file announces itself once the import has finished, so a client
	// never opens a presentation whose pictures are still arriving.
	dest := uploadutil.Destination{Registry: params.Registry, Storage: params.Storage}
	var media []string
	storeMedia := func(name string, r io.Reader) (string, error) {
		written, err := dest.WriteFile(uploadutil.WriteFileParams{
			Ctx:      params.Ctx,
			Reader:   r,
			RootDir:  mediaDir,
			FileName: name,
			Serial:   params.Serial,
			KeepBoth: true,
		})
		if err != nil {
			return "", err
		}
		media = append(media, written.Path)
		return written.Path, nil
	}

	pr, pw := io.Pipe()
	imported := make(chan importOutcome, 1)
	go func() {
		result, err := pptxutil.ImportPptx(pptxutil.ImportPptxParams{
			Source:     source,
			Size:       size,
			Out:        pw,
			StoreMedia: storeMedia,
			Title:      stem,
		})
		// Closing with the error is what stops the destination from storing a
		// truncated presentation as if it were whole.
		pw.CloseWithError(err)
		imported <- importOutcome{result: result, err: err}
	}()

	written, writeErr := dest.WriteFile(uploadutil.WriteFileParams{
		Ctx:      params.Ctx,
		Reader:   pr,
		RootDir:  rootDir,
		FileName: stem + ".qslide",
		Serial:   params.Serial,
		KeepBoth: true,
	})
	// Unblocks the import if the destination gave up first.
	pr.CloseWithError(writeErr)
	outcome := <-imported

	if outcome.err != nil || writeErr != nil {
		discardImport(params, media, mediaDir, mediaDirExisted)
		if outcome.err != nil {
			return ImportPptxResult{}, importError(outcome.err)
		}
		return ImportPptxResult{}, writeErr
	}

	publish := func(dir string) {
		if params.EventBus != nil {
			params.EventBus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: dir})
		}
	}
	publish(rootDir)
	result := ImportPptxResult{
		Path:     written.Path,
		Media:    media,
		Slides:   outcome.result.Slides,
		Pictures: outcome.result.Pictures,
		Warnings: outcome.result.Warnings,
	}
	if len(media) > 0 {
		result.MediaDir = mediaDir
		result.MediaDirCreated = !mediaDirExisted
		publish(mediaDir)
	}
	return result, nil
}

// IsPptxPath reports whether a path names a presentation this can import:
// a .pptx, or the macro-enabled .pptm and slide-show .ppsx that share its
// format. The legacy binary .ppt does not.
func IsPptxPath(filePath string) bool {
	switch strings.ToLower(filepath.Ext(filePath)) {
	case ".pptx", ".pptm", ".ppsx":
		return true
	}
	return false
}

// importOutcome carries what the import goroutine produced back to the
// caller, so an import failure is reported as itself rather than as the
// broken-pipe write error it causes.
type importOutcome struct {
	result pptxutil.ImportPptxResult
	err    error
}

// importError makes a package that is malformed or past the import limits
// the caller's file, not a server fault.
func importError(err error) error {
	if errors.Is(err, pptxutil.ErrNotPptx) || errors.Is(err, pptxutil.ErrTooLarge) {
		return &UnsupportedError{Err: err}
	}
	return err
}

// discardImport removes the pictures an import that failed had stored, and
// their folder when the import created it. The .qslide itself is written
// atomically, so a failed one never lands. It is best effort: the error that
// got us here is the one worth reporting.
func discardImport(params ImportPptxParams, media []string, mediaDir string, mediaDirExisted bool) {
	remove := ConvertXlsxParams{Ctx: params.Ctx, Registry: params.Registry, Storage: params.Storage, Serial: params.Serial}
	for _, p := range media {
		discardTemp(remove, p)
	}
	if len(media) > 0 && !mediaDirExisted {
		discardTemp(remove, mediaDir)
	}
	if len(media) > 0 {
		slog.Info("pptx: removed the pictures of a failed import", "path", params.FilePath, "count", len(media))
	}
}
