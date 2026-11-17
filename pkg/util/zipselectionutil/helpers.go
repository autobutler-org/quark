package zipselectionutil

import (
	"archive/zip"
	"compress/flate"
	"fmt"
	"io"
	"path"
	"strings"
	"sync"
	"time"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/fileutil"
)

// skippedHeader opens the skipped list.
const skippedHeader = "These items could not be added to this zip. They may have been moved or deleted, " +
	"or you may not have access to them. Folders are not included.\n\n"

// add zips one selected file, or records it as skipped.
func (z *selectionZip) add(p Path) error {
	if err := z.ctx.Err(); err != nil {
		return err
	}
	key := Path{Serial: p.Serial, FilePath: accessutil.Canonical(p.FilePath)}
	if z.seen[key] {
		return nil
	}
	z.seen[key] = true

	if !z.access.Check(p.Serial, p.FilePath, accessutil.Read).Readable {
		z.skip(p)
		return nil
	}
	fsys, err := fileutil.FilesVFS(z.registry, p.Serial)
	if err != nil {
		z.skip(p)
		return nil
	}
	info, err := fsys.Stat(z.ctx, p.FilePath)
	if err != nil || info.IsDir {
		z.skip(p)
		return nil
	}
	r, err := fsys.Open(z.ctx, p.FilePath)
	if err != nil {
		z.skip(p)
		return nil
	}
	defer r.Close()

	name := z.names.claim(path.Base(key.FilePath))
	w, err := z.zw.CreateHeader(&zip.FileHeader{
		Name:               name,
		Method:             fileutil.ZipMethod(info.Name, info.MimeType, info.Size),
		Modified:           info.ModTime,
		UncompressedSize64: uint64(max(info.Size, 0)),
	})
	if err != nil {
		return fmt.Errorf("failed to create zip entry %s: %w", name, err)
	}
	// The reader is wrapped so a WriteTo cannot bypass buf and allocate its
	// own per entry.
	if _, err := io.CopyBuffer(w, struct{ io.Reader }{r}, z.buf); err != nil {
		return fmt.Errorf("failed to write zip entry %s: %w", name, err)
	}
	z.result.Entries++
	return nil
}

func (z *selectionZip) skip(p Path) {
	z.result.Skipped = append(z.result.Skipped, p)
}

// writeSkipped ends the archive with the list of what was left out, when
// anything was.
func (z *selectionZip) writeSkipped() error {
	if len(z.result.Skipped) == 0 {
		return nil
	}
	name := z.names.claim(SkippedListName)
	w, err := z.zw.CreateHeader(&zip.FileHeader{Name: name, Method: zip.Deflate, Modified: time.Now()})
	if err != nil {
		return fmt.Errorf("failed to create %s: %w", name, err)
	}
	if _, err := io.WriteString(w, skippedHeader); err != nil {
		return fmt.Errorf("failed to write %s: %w", name, err)
	}
	for _, p := range z.result.Skipped {
		line := p.FilePath
		if p.Serial != "" {
			line = p.Serial + ": " + line
		}
		if _, err := io.WriteString(w, line+"\n"); err != nil {
			return fmt.Errorf("failed to write %s: %w", name, err)
		}
	}
	return nil
}

// claim returns name, or name numbered " (1)", " (2)", ... before its
// extension when an earlier entry has it, and marks the result taken.
func (n entryNames) claim(name string) string {
	stem, ext := name, path.Ext(name)
	if ext != name {
		stem = strings.TrimSuffix(name, ext)
	} else {
		ext = ""
	}
	candidate := name
	for i := 1; n.taken[strings.ToLower(candidate)]; i++ {
		candidate = fmt.Sprintf("%s (%d)%s", stem, i, ext)
	}
	n.taken[strings.ToLower(candidate)] = true
	return candidate
}

// newSelectionZipWriter is a zip.Writer onto w whose Deflate runs at the
// fastest level: a selection download is bound by how fast it compresses, not
// by bytes saved. Photos and video are stored and never reach it.
func newSelectionZipWriter(w io.Writer) *zip.Writer {
	zw := zip.NewWriter(w)
	zw.RegisterCompressor(zip.Deflate, pooledCompressor)
	return zw
}

// flateWriters pools compressors across entries and archives: a flate.Writer
// is ~600 KiB, and a selection of 2,000 documents would otherwise make one
// per entry.
var flateWriters sync.Pool

// pooledFlateWriter returns its compressor to flateWriters on Close.
type pooledFlateWriter struct {
	*flate.Writer
}

func (w pooledFlateWriter) Close() error {
	err := w.Writer.Close()
	flateWriters.Put(w.Writer)
	return err
}

func pooledCompressor(out io.Writer) (io.WriteCloser, error) {
	if fw, ok := flateWriters.Get().(*flate.Writer); ok {
		fw.Reset(out)
		return pooledFlateWriter{fw}, nil
	}
	fw, err := flate.NewWriter(out, flate.BestSpeed)
	if err != nil {
		return nil, err
	}
	return pooledFlateWriter{fw}, nil
}
