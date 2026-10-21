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
	"github.com/autobutler-org/quark/pkg/util/odputil"
	"github.com/autobutler-org/quark/pkg/util/pptxutil"
	"github.com/autobutler-org/quark/pkg/util/uploadutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ImportPptxParams imports one PowerPoint file as a .qslide the Slides editor
// opens.
type ImportPptxParams struct {
	// Ctx bounds the read and the writes.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
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
	Warnings []SlideWarning
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
	return importSlides(params, readPptx)
}

// importSlides writes the presentation read turns into .qslide JSON in
// params.RootDir, with its pictures in a <name>_media folder beside it: the
// import every presentation format shares once its extension is checked.
func importSlides(params ImportPptxParams, read slideReader) (ImportPptxResult, error) {
	if climbsOut(params.RootDir) {
		return ImportPptxResult{}, invalidPath(params.RootDir)
	}
	rootDir := cleanRelPath(params.RootDir)
	if rootDir == "." {
		rootDir = ""
	}
	base := path.Base(cleanRelPath(params.FilePath))
	stem := strings.TrimSuffix(base, filepath.Ext(base))
	mediaDir := pptxutil.MediaDir(rootDir, stem)
	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return ImportPptxResult{}, err
	}
	mediaDirExisted, err := exists(params.Ctx, fsys, mediaDir)
	if err != nil {
		return ImportPptxResult{}, err
	}

	source, size, closer, err := openZip(params.Ctx, fsys, params.FilePath)
	if err != nil {
		return ImportPptxResult{}, err
	}
	defer closer.Close()

	// Each file announces itself once the import has finished, so a client
	// never opens a presentation whose pictures are still arriving.
	dest := uploadutil.Destination{Registry: params.Registry}
	var media []string
	storeMedia := func(_, name string, r io.Reader) (string, error) {
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
		result, err := read(params.Ctx, source, size, pw, storeMedia, stem)
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
		discardImport(params, fsys, media, mediaDir, mediaDirExisted)
		if outcome.err != nil {
			return ImportPptxResult{}, importError(outcome.err)
		}
		return ImportPptxResult{}, writeErr
	}

	publish := func(dir string) {
		if params.EventBus != nil {
			params.EventBus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: dir, DeviceSerial: params.Serial})
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

// slideReader reads one presentation format from source, size bytes long,
// and writes it to out as .qslide JSON, handing each picture to store.
// Title names the deck when the file names none.
type slideReader func(ctx context.Context, source io.ReaderAt, size int64, out io.Writer,
	store pptxutil.StoreMediaFunc, title string) (slideOutcome, error)

// slideOutcome is what a [slideReader] read.
type slideOutcome struct {
	Slides   int
	Pictures int
	Warnings []SlideWarning
}

// slideReaderFor picks the reader for a presentation by its extension, not
// ok for a file that is not one Quark can read.
func slideReaderFor(filePath string) (slideReader, bool) {
	switch {
	case IsPptxPath(filePath):
		return readPptx, true
	case IsOdpPath(filePath):
		return readOdp, true
	}
	return nil, false
}

// readPptx is the [slideReader] for PowerPoint. The reader takes no
// context; a caller that needs a deadline puts it on source.
func readPptx(_ context.Context, source io.ReaderAt, size int64, out io.Writer,
	store pptxutil.StoreMediaFunc, title string) (slideOutcome, error) {
	imported, err := pptxutil.ImportPptx(pptxutil.ImportPptxParams{
		Source:     source,
		Size:       size,
		Out:        out,
		StoreMedia: store,
		Title:      title,
	})
	warnings := make([]SlideWarning, 0, len(imported.Warnings))
	for _, w := range imported.Warnings {
		warnings = append(warnings, SlideWarning(w))
	}
	return slideOutcome{Slides: imported.Slides, Pictures: imported.Pictures, Warnings: warnings}, err
}

// importOutcome carries what the import goroutine produced back to the
// caller, so an import failure is reported as itself rather than as the
// broken-pipe write error it causes.
type importOutcome struct {
	result slideOutcome
	err    error
}

// importError makes a package that is malformed, encrypted or past the
// import limits the caller's file, not a server fault.
func importError(err error) error {
	if errors.Is(err, pptxutil.ErrNotPptx) || errors.Is(err, pptxutil.ErrTooLarge) ||
		errors.Is(err, odputil.ErrMalformed) || errors.Is(err, odputil.ErrTooLarge) ||
		errors.Is(err, odputil.ErrEncrypted) {
		return &UnsupportedError{Err: err}
	}
	return err
}

// discardImport removes the pictures an import that failed had stored, and
// their folder when the import created it. The .qslide itself is written
// atomically, so a failed one never lands. It is best effort: the error that
// got us here is the one worth reporting.
func discardImport(params ImportPptxParams, fsys vfs.VFS, media []string, mediaDir string, mediaDirExisted bool) {
	for _, p := range media {
		discardTemp(params.Ctx, fsys, p)
	}
	if len(media) > 0 && !mediaDirExisted {
		discardTemp(params.Ctx, fsys, mediaDir)
	}
	if len(media) > 0 {
		slog.Info("slides: removed the pictures of a failed import", "path", params.FilePath, "count", len(media))
	}
}
