package fileutil

import (
	"archive/zip"
	"bufio"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"math"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/photoutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/mholt/archiver/v4"
	"github.com/nwaples/rardecode/v2"
)

// Every archive operation reads the archive out of the files namespace of the
// device the request names, for every format Quark supports (#2644). A zip or
// 7z is read in place through the vfs.File's ReadAt, a tar or rar is streamed,
// and nothing is ever buffered whole: buffering is what turned a 4 GiB archive
// into a 500 when io.ReadAll wanted ~12 GiB of heap to hold it (#1705).

// ArchiveLimits bounds what Quark reads out of an archive. Everything an
// archive says about itself is the uploader's to choose, so no header is
// trusted: a declared size only turns an honest archive away early, and the
// bytes actually decompressed are counted as they stream. A zero field takes
// its value from [DefaultArchiveLimits].
//
// An archive inside an archive is never opened (FindArchive stops at the
// first archive in a path), so archives nest one deep by construction;
// MaxDepth bounds the folders inside one.
type ArchiveLimits struct {
	// MaxEntries is the most entries a walk reads before it refuses the
	// archive, so a central directory of millions of names cannot pin the
	// CPU or a listing's memory.
	MaxEntries int
	// MaxEntryBytes is the most bytes one entry may declare or decompress
	// to, whether it is read, served or extracted.
	MaxEntryBytes int64
	// MaxTotalBytes is the most bytes the entries of one archive may declare
	// between them, and the most an extraction writes. A zip bomb declares
	// petabytes (42.zip, or the overlapping-entry kind), so listing it is
	// refused before anything is decompressed.
	MaxTotalBytes int64
	// MaxDepth is the most path segments an entry name may have.
	MaxDepth int
}

// DefaultArchiveLimits are the limits every archive operation applies unless
// its Params say otherwise. They are far above what a real archive needs and
// far below what a crafted one claims: a backup tar of a few hundred gigabytes
// opens, a bomb declaring terabytes does not.
func DefaultArchiveLimits() ArchiveLimits {
	return ArchiveLimits{
		MaxEntries:    100_000,
		MaxEntryBytes: 10 << 30,  // 10 GiB
		MaxTotalBytes: 256 << 30, // 256 GiB
		MaxDepth:      128,
	}
}

// orDefault fills every zero field from [DefaultArchiveLimits].
func (l ArchiveLimits) orDefault() ArchiveLimits {
	d := DefaultArchiveLimits()
	if l.MaxEntries <= 0 {
		l.MaxEntries = d.MaxEntries
	}
	if l.MaxEntryBytes <= 0 {
		l.MaxEntryBytes = d.MaxEntryBytes
	}
	if l.MaxTotalBytes <= 0 {
		l.MaxTotalBytes = d.MaxTotalBytes
	}
	if l.MaxDepth <= 0 {
		l.MaxDepth = d.MaxDepth
	}
	return l
}

// ArchiveLimit names the field of [ArchiveLimits] an archive tripped.
type ArchiveLimit string

// The limits an [ArchiveLimitError] can name.
const (
	ArchiveLimitEntries    ArchiveLimit = "entries"
	ArchiveLimitEntryBytes ArchiveLimit = "entry size"
	ArchiveLimitTotalBytes ArchiveLimit = "total size"
	ArchiveLimitDepth      ArchiveLimit = "depth"
)

// ArchiveLimitError reports an archive refused for tripping one of its
// [ArchiveLimits]. It always arrives inside an [UnsupportedError], so the
// handler answers it with 400 and the message reaches the client.
type ArchiveLimitError struct {
	// Limit is the limit tripped.
	Limit ArchiveLimit
	// Max is that limit's value.
	Max int64
	// Entry is the entry that tripped it, empty when the archive as a whole
	// did.
	Entry string
}

func (e *ArchiveLimitError) Error() string {
	switch e.Limit {
	case ArchiveLimitEntries:
		return fmt.Sprintf("archive exceeds maximum of %d entries", e.Max)
	case ArchiveLimitEntryBytes:
		return fmt.Sprintf("archive entry %q exceeds maximum allowed size of %d bytes", e.Entry, e.Max)
	case ArchiveLimitTotalBytes:
		return fmt.Sprintf("archive exceeds maximum total size of %d bytes when decompressed", e.Max)
	default:
		return fmt.Sprintf("archive entry %q exceeds maximum folder depth of %d", e.Entry, e.Max)
	}
}

// UnsafeArchiveEntryError reports an archive refused because an entry's name
// climbs out of it ("../x", "a/../../x", "..\x"): written out, it would land
// outside the folder the archive extracts into (Zip Slip). The whole archive
// is refused rather than the entry skipped, since nothing makes such a name
// but a tool trying it on. It arrives inside an [UnsupportedError].
type UnsafeArchiveEntryError struct {
	// Entry is the name as the archive gives it.
	Entry string
}

func (e *UnsafeArchiveEntryError) Error() string {
	return fmt.Sprintf("archive entry %q points outside the archive, so the archive was not opened", e.Entry)
}

// EncryptedArchiveError reports an archive, or an entry in one, that needs a
// password. Quark asks for none, so it cannot be read. It arrives inside an
// [UnsupportedError].
type EncryptedArchiveError struct {
	// Name is the encrypted entry, or the archive when its headers are
	// encrypted too.
	Name string
}

func (e *EncryptedArchiveError) Error() string {
	return fmt.Sprintf("%s is password-protected; Quark cannot open encrypted archives", e.Name)
}

// ListArchiveParams lists one level inside an archive. Nothing is extracted:
// only the entry headers are read.
type ListArchiveParams struct {
	// Ctx bounds the read.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// Limits bounds the walk; the zero value is [DefaultArchiveLimits].
	Limits ArchiveLimits
	// FilePath is the archive, relative to the device files directory.
	FilePath string
	// SubPath is the virtual directory inside the archive, empty for its root.
	SubPath string
	// Serial identifies the device, empty for the internal one.
	Serial string
}

// ListArchiveResult is the direct children of the requested level.
type ListArchiveResult struct {
	Entries []FileNode
}

// ListArchive returns the direct children of SubPath inside the archive at
// FilePath, folders first, as virtual paths the client passes back to list
// deeper.
func ListArchive(params ListArchiveParams) (ListArchiveResult, error) {
	archive, err := openFilesArchive(params.Ctx, params.Registry, params.Serial, params.FilePath, params.Limits)
	if err != nil {
		return ListArchiveResult{}, err
	}
	defer archive.Close()

	sub := entryName(params.SubPath)
	prefix := ""
	if sub != "" {
		prefix = sub + "/"
	}
	// The virtual path the client passes back as filePath to list deeper.
	virtualDir := path.Join(filepath.ToSlash(params.FilePath), sub)

	seen := make(map[string]struct{})
	result := []FileNode{}
	err = archive.walk(params.Ctx, func(e archiveEntry) error {
		rel, ok := strings.CutPrefix(e.name, prefix)
		if !ok || rel == "" {
			return nil
		}
		// Only the direct child: anything deeper names a folder, which the
		// archive may only imply.
		childName, _, deeper := strings.Cut(rel, "/")
		if _, exists := seen[childName]; exists {
			return nil
		}
		seen[childName] = struct{}{}

		node := FileNode{
			Name:         childName,
			IsDir:        e.isDir || deeper,
			DirPath:      path.Join(virtualDir, childName),
			FullPath:     path.Join(virtualDir, childName),
			DeviceSerial: params.Serial,
		}
		if !deeper {
			// A folder the archive only implies has no size or time of its
			// own; this entry's belong to something inside it.
			node.Size = max(e.size, 0)
			node.CompressedSize = e.compressedSize
			node.ModifiedAt = archiveEntryTime(e.modTime)
		}
		if !node.IsDir {
			node.FileType = string(storageutil.DetermineFileTypeFromPath(childName))
		}
		result = append(result, node)
		return nil
	})
	if err != nil {
		return ListArchiveResult{}, err
	}

	slices.SortStableFunc(result, func(a, b FileNode) int {
		if a.IsDir != b.IsDir {
			if a.IsDir {
				return -1
			}
			return 1
		}
		return strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
	})
	return ListArchiveResult{Entries: result}, nil
}

// archiveEntryTime is an entry's modification time, or the zero time when the
// archive does not really say. A zip entry written without one reads back as
// 1979-11-30, the DOS date zero, so anything before the DOS epoch counts as
// unset rather than as a date to show.
func archiveEntryTime(t time.Time) time.Time {
	if t.Year() < 1980 {
		return time.Time{}
	}
	return t
}

// OpenArchiveEntryParams reads one entry out of an archive without extracting
// anything.
type OpenArchiveEntryParams struct {
	// Ctx bounds the read.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// Limits bounds the walk and the entry's stream; the zero value is
	// [DefaultArchiveLimits].
	Limits ArchiveLimits
	// ArchivePath is the archive, relative to the device files directory.
	ArchivePath string
	// EntryPath is the entry inside the archive.
	EntryPath string
	// Serial identifies the device, empty for the internal one.
	Serial string
	// WantsJPEG asks for an image entry to come back as JPEG.
	WantsJPEG bool
}

// OpenArchiveEntryResult is the entry's stream. The caller closes the reader.
type OpenArchiveEntryResult struct {
	// Reader streams the decompressed entry.
	Reader io.ReadCloser
	// Size is the entry's length, negative when the archive does not say.
	Size int64
	// Kind is DownloadJPEG when the entry has to be converted, otherwise
	// DownloadContents.
	Kind DownloadKind
	// FileName is the name the client is offered in Content-Disposition.
	FileName string
	// ContentType is the type to serve.
	ContentType string
}

// OpenArchiveEntry opens a single entry inside an archive for streaming, and
// says whether it has to be converted to JPEG on the way out.
func OpenArchiveEntry(params OpenArchiveEntryParams) (OpenArchiveEntryResult, error) {
	entry, err := openArchiveEntryStream(params)
	if err != nil {
		return OpenArchiveEntryResult{}, err
	}

	// RAW previews come from an external tool that needs an OS path, and an
	// entry is only a stream, so RAW entries are served as they are (#1851).
	// The device has no HEIC decoder, so HEIC entries are too (#2382).
	if params.WantsJPEG &&
		storageutil.DetermineFileTypeFromPath(params.EntryPath) == storageutil.FileTypeImage &&
		!photoutil.IsRawFile(params.EntryPath) && !photoutil.IsHEICFile(params.EntryPath) {
		entry.Kind = DownloadJPEG
		entry.FileName = JPEGFileName(params.EntryPath)
		entry.ContentType = "image/jpeg"
		return entry, nil
	}

	entry.Kind = DownloadContents
	entry.FileName = filepath.Base(params.EntryPath)
	entry.ContentType = "application/octet-stream"
	return entry, nil
}

// FindArchiveParams asks whether a files path names an entry inside an archive.
type FindArchiveParams struct {
	// Ctx bounds the stat.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// FilePath is the requested path, relative to the device files directory.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
}

// FindArchiveResult is the archive and entry a files path names.
type FindArchiveResult struct {
	// Found is false when no folder segment of the path is an archive file.
	Found bool
	// ArchivePath is the archive, relative to the device files directory.
	ArchivePath string
	// EntryPath is the entry inside the archive.
	EntryPath string
	// ModTime is the archive's modification time.
	ModTime time.Time
}

// FindArchive reports whether a files path names an entry inside an archive:
// "a/photos.zip/pics/red.png" is the entry "pics/red.png" of "a/photos.zip"
// when that is a file. A folder only named like an archive does not count, nor
// does a path that does not exist. The archive is stat-ed rather than opened,
// so a cache keyed on its modification time stays cheap to check.
func FindArchive(params FindArchiveParams) (FindArchiveResult, error) {
	segments := strings.Split(strings.Trim(filepath.ToSlash(params.FilePath), "/"), "/")
	for i, segment := range segments[:len(segments)-1] {
		// path.Ext of "x.tar.gz" is ".gz", which is in the set as well.
		if !slices.Contains(storageutil.SupportedArchiveExts(), strings.ToLower(path.Ext(segment))) {
			continue
		}
		archivePath := strings.Join(segments[:i+1], "/")
		info, err := statFilesPath(params, archivePath)
		if err != nil || info == nil {
			return FindArchiveResult{}, err
		}
		if info.IsDir {
			continue
		}
		return FindArchiveResult{
			Found:       true,
			ArchivePath: archivePath,
			EntryPath:   strings.Join(segments[i+1:], "/"),
			ModTime:     info.ModTime,
		}, nil
	}
	return FindArchiveResult{}, nil
}

// statFilesPath stats a files path on the namespace of the device the request
// names. A path that does not resolve — on a device that is not attached, too
// — is nil with no error; the caller's own lookup of the full path reports it.
func statFilesPath(params FindArchiveParams, filePath string) (*vfs.FileInfo, error) {
	fsys, err := FilesVFS(params.Registry, params.Serial)
	var notFound *NotFoundError
	if errors.As(err, &notFound) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	info, err := fsys.Stat(params.Ctx, filePath)
	if errors.Is(err, vfs.ErrNotFound) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to stat %s: %w", filePath, err)
	}
	return &info, nil
}

// openArchiveEntryStream finds an entry and opens its decompressed stream.
// The stream reads out of the archive, so the archive closes with it.
func openArchiveEntryStream(params OpenArchiveEntryParams) (OpenArchiveEntryResult, error) {
	archive, err := openFilesArchive(params.Ctx, params.Registry, params.Serial, params.ArchivePath, params.Limits)
	if err != nil {
		return OpenArchiveEntryResult{}, err
	}

	want := entryName(params.EntryPath)
	var found *OpenArchiveEntryResult
	err = archive.walk(params.Ctx, func(e archiveEntry) error {
		if want == "" || e.name != want {
			return nil
		}
		if e.isDir || e.isLink {
			return notFoundf("entry %q is not a file", params.EntryPath)
		}
		if e.size > archive.limits.MaxEntryBytes {
			return entryTooLarge(e.name, archive.limits)
		}
		rc, err := e.open()
		if err != nil {
			return err
		}
		// The first bytes are read here, before the caller commits to a
		// status: a password the entry needs, or a corrupt stream, is an
		// error the handler can still answer rather than a cut-off body.
		buffered := bufio.NewReader(&capReader{r: rc, left: archive.limits.MaxEntryBytes, name: e.name, limits: archive.limits})
		if _, err := buffered.Peek(1); err != nil && !errors.Is(err, io.EOF) {
			rc.Close()
			return err
		}
		found = &OpenArchiveEntryResult{Reader: entryReader{Reader: buffered, entry: rc, archive: archive}, Size: e.size}
		// A streamed format can only be read from where the walk stands, so
		// the walk stops here and leaves the stream on this entry.
		return errEntryFound
	})
	if found != nil {
		return *found, nil
	}
	archive.Close()
	if err != nil {
		return OpenArchiveEntryResult{}, err
	}
	return OpenArchiveEntryResult{}, notFoundf("entry %q not found in archive", params.EntryPath)
}

// errEntryFound stops a walk at the entry being opened.
var errEntryFound = errors.New("entry found")

// entryReader reads a streaming entry, capped at the entry limit, and keeps
// the archive open behind it until the entry closes.
type entryReader struct {
	io.Reader
	entry   io.Closer
	archive io.Closer
}

func (e entryReader) Close() error {
	err := e.entry.Close()
	if cerr := e.archive.Close(); err == nil {
		err = cerr
	}
	return err
}

// ExtractArchiveParams extracts an archive beside itself.
type ExtractArchiveParams struct {
	// Ctx bounds the extraction: a multi-gigabyte archive takes minutes, and
	// it stops when the caller goes away.
	Ctx context.Context
	// Registry holds the namespace of the device Serial names.
	Registry vfs.Registry
	// EventBus is told about the item that appeared. Nil publishes nothing.
	EventBus *eventbus.Bus
	// Limits bounds the walk and every byte written; the zero value is
	// [DefaultArchiveLimits].
	Limits ArchiveLimits
	// FilePath is the archive, relative to the device files directory.
	FilePath string
	// Serial identifies the device, empty for the internal one.
	Serial string
}

// ExtractArchiveResult reports what an extraction made.
type ExtractArchiveResult struct {
	// CreatedPath is the new item, files-relative: the folder the archive's
	// entries landed in, or the file a bare compressed stream decompressed to.
	// It is named after the archive, numbered when that name is taken, so it
	// is always new.
	CreatedPath string
}

// ExtractArchive extracts the archive at FilePath into a new folder beside it
// named after the archive, or decompresses a bare compressed stream (a .gz
// that holds no tar) to a new file beside it. Every entry streams out of the
// archive and back in through VFS.Write. The folder is filled under a hidden
// name and moved into place once every entry is in it, so an extraction that
// fails partway leaves nothing behind under a name a user would see.
func ExtractArchive(params ExtractArchiveParams) (ExtractArchiveResult, error) {
	fsys, err := FilesVFS(params.Registry, params.Serial)
	if err != nil {
		return ExtractArchiveResult{}, err
	}
	archive, err := openArchive(params.Ctx, fsys, params.FilePath, params.Limits)
	if err != nil {
		return ExtractArchiveResult{}, err
	}
	defer archive.Close()

	dir := path.Dir(filepath.ToSlash(params.FilePath))
	stem := storageutil.ArchiveStem(params.FilePath)
	kind := eventbus.EventNewFolder
	var created string
	if archive.decompressor != nil {
		kind = eventbus.EventUpload
		created, err = decompressInto(params.Ctx, fsys, archive, dir, stem)
	} else {
		created, err = extractInto(params.Ctx, fsys, archive, dir, stem)
	}
	if err != nil {
		return ExtractArchiveResult{}, err
	}

	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{Kind: kind, Path: created, DeviceSerial: params.Serial})
	}
	return ExtractArchiveResult{CreatedPath: created}, nil
}

// extractInto extracts every entry of archive into a hidden folder in dir and
// moves it to the first free name taken from stem once it is complete. The
// hidden folder is removed when anything fails.
func extractInto(ctx context.Context, fsys vfs.VFS, archive *openedArchive, dir, stem string) (string, error) {
	staging := path.Join(dir, storageutil.WriteTempPrefix+"extract-"+rand.Text())
	if err := fsys.MkdirAll(ctx, staging); err != nil {
		return "", fmt.Errorf("failed to create destination directory: %w", err)
	}

	err := archive.walk(ctx, func(e archiveEntry) error {
		// A link can point anywhere, out of the folder included.
		if e.isLink {
			return nil
		}
		dest := path.Join(staging, e.name)
		if e.isDir {
			return fsys.MkdirAll(ctx, dest)
		}
		if err := fsys.MkdirAll(ctx, path.Dir(dest)); err != nil {
			return fmt.Errorf("failed to create parent directory for %s: %w", e.name, err)
		}
		return writeEntry(ctx, fsys, archive, dest, e)
	})
	var created string
	if err == nil {
		created, err = freeName(ctx, fsys, dir, stem)
	}
	if err == nil {
		err = fsys.Move(ctx, staging, created)
	}
	if err != nil {
		// The caller may have gone away, which is what stopped the walk; the
		// half-filled folder is removed regardless.
		if delErr := fsys.Delete(context.WithoutCancel(ctx), staging, vfs.DeleteOptions{Recursive: true}); delErr != nil {
			slog.Error("extract: could not remove a failed extraction", "path", staging, "err", delErr)
		}
		return "", err
	}
	return created, nil
}

// decompressInto writes a bare compressed stream to the first free name in dir
// taken from stem. VFS.Write lands it under that name only once it is whole.
func decompressInto(ctx context.Context, fsys vfs.VFS, archive *openedArchive, dir, stem string) (string, error) {
	created, err := freeName(ctx, fsys, dir, stem)
	if err != nil {
		return "", err
	}
	err = archive.walk(ctx, func(e archiveEntry) error {
		return writeEntry(ctx, fsys, archive, created, e)
	})
	if err != nil {
		return "", err
	}
	return created, nil
}

// writeEntry streams one entry of archive to dest, refusing it when it is
// over the entry limit or takes the extraction over the total one. The
// declared size turns away an honest oversized entry outright; capReader
// refuses one whose header lied, and since VFS.Write only lands a complete
// stream, nothing is left at dest either way. IfNoneMatch keeps a
// decompressed file from replacing one that appeared after its name was
// chosen.
func writeEntry(ctx context.Context, fsys vfs.VFS, archive *openedArchive, dest string, e archiveEntry) error {
	if e.size > archive.limits.MaxEntryBytes {
		return entryTooLarge(e.name, archive.limits)
	}
	rc, err := e.open()
	if err != nil {
		return err
	}
	defer rc.Close()
	capped := &capReader{
		r: rc, left: archive.limits.MaxEntryBytes, total: &archive.unwritten,
		name: e.name, limits: archive.limits,
	}
	if err := fsys.Write(ctx, dest, capped, vfs.WriteOptions{IfNoneMatch: "*"}); err != nil {
		return fmt.Errorf("failed to write %s: %w", e.name, err)
	}
	return nil
}

// capReader reads r and fails once it has given more than left bytes, or
// more than total has left between every capReader sharing it.
type capReader struct {
	r    io.Reader
	left int64
	// total is the archive-wide budget, nil when only the entry is counted.
	total  *int64
	name   string
	limits ArchiveLimits
}

func (c *capReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.left -= int64(n)
	if c.left < 0 {
		return 0, entryTooLarge(c.name, c.limits)
	}
	if c.total != nil {
		*c.total -= int64(n)
		if *c.total < 0 {
			return 0, limitError(ArchiveLimitTotalBytes, c.limits.MaxTotalBytes, "")
		}
	}
	return n, err
}

// entryTooLarge refuses an entry over the per-entry limit.
func entryTooLarge(name string, limits ArchiveLimits) error {
	return limitError(ArchiveLimitEntryBytes, limits.MaxEntryBytes, name)
}

// limitError refuses an archive for tripping limit. The archive is the
// caller's, so it is an [UnsupportedError]: a 400.
func limitError(limit ArchiveLimit, maxValue int64, entry string) error {
	return &UnsupportedError{Err: &ArchiveLimitError{Limit: limit, Max: maxValue, Entry: entry}}
}

// freeName returns dir/name, or the first numbered name beside it that nothing
// occupies.
func freeName(ctx context.Context, fsys vfs.VFS, dir, name string) (string, error) {
	for n := 0; ; n++ {
		p := path.Join(dir, storageutil.NumberedName(name, n))
		_, err := fsys.Stat(ctx, p)
		if errors.Is(err, vfs.ErrNotFound) {
			return p, nil
		}
		if err != nil {
			return "", fmt.Errorf("failed to stat %s: %w", p, err)
		}
	}
}

// archiveEntry is one entry of an archive, whatever its format.
type archiveEntry struct {
	// name is the entry's path, slash-separated, with no leading or trailing
	// slash. See entryName.
	name   string
	isDir  bool
	isLink bool
	// size is the decompressed length, negative when the archive does not say.
	size int64
	// compressedSize is the stored length, zero when the format does not say.
	compressedSize int64
	modTime        time.Time
	open           func() (io.ReadCloser, error)
}

// openedArchive is an archive open for reading. Exactly one of zip, extractor
// and decompressor is set.
type openedArchive struct {
	file vfs.File
	path string
	// limits bounds every walk and every entry read.
	limits ArchiveLimits
	// unwritten is what is left of limits.MaxTotalBytes for an extraction,
	// counted down by every entry written.
	unwritten int64
	// zip reads a zip (.zip, or one named .cbz, .jar, .apk or .whl) in place
	// through the file's ReadAt. It is Go's own
	// reader rather than archiver's so an unsupported compression method
	// can be named (openZipEntry).
	zip *zip.Reader
	// extractor walks every other archive format.
	extractor archiver.Extractor
	// decompressor reads a bare compressed stream, which holds one file.
	decompressor archiver.Decompressor
	// input is the stream extractor and decompressor read: the file itself,
	// rewound, since a vfs.File seeks.
	input io.Reader
}

// openFilesArchive opens the archive at p in the files namespace of the device
// serial names. A device that is not attached is a [NotFoundError].
func openFilesArchive(ctx context.Context, registry vfs.Registry, serial, p string, limits ArchiveLimits) (*openedArchive, error) {
	fsys, err := FilesVFS(registry, serial)
	if err != nil {
		return nil, err
	}
	return openArchive(ctx, fsys, p, limits)
}

// openArchive opens the archive at p in fsys and identifies its format. A
// name Quark does not read as an archive, or content no format matches, is an
// [UnsupportedError]; a path that cannot be opened is a [NotFoundError].
func openArchive(ctx context.Context, fsys vfs.VFS, p string, limits ArchiveLimits) (*openedArchive, error) {
	if !storageutil.IsSupportedArchive(p) {
		return nil, &UnsupportedError{Err: fmt.Errorf("%s is not an archive: supported formats are %s",
			path.Base(p), strings.Join(storageutil.SupportedArchiveExts(), ", "))}
	}
	f, err := fsys.Open(ctx, p)
	if err != nil {
		return nil, notFound(fmt.Errorf("file not found: %s: %w", p, err))
	}
	limits = limits.orDefault()
	archive := &openedArchive{file: f, path: p, limits: limits, unwritten: limits.MaxTotalBytes}
	if err := archive.identify(ctx); err != nil {
		f.Close()
		return nil, err
	}
	return archive, nil
}

// identify works out which reader the archive needs.
func (a *openedArchive) identify(ctx context.Context) error {
	if storageutil.IsZipArchive(a.path) {
		size, err := a.file.Seek(0, io.SeekEnd)
		if err != nil {
			return fmt.Errorf("failed to size archive: %w", err)
		}
		// ErrInsecurePath (under GODEBUG=zipinsecurepath=0) comes with a
		// usable reader; walk refuses the escaping name itself, with the
		// error that names it.
		a.zip, err = zip.NewReader(a.file, size)
		if err != nil && !errors.Is(err, zip.ErrInsecurePath) {
			return &UnsupportedError{Err: fmt.Errorf("%s is not a readable zip archive: %w", path.Base(a.path), err)}
		}
		return nil
	}

	format, input, err := archiver.Identify(ctx, path.Base(a.path), a.file)
	if errors.Is(err, archiver.NoMatch) {
		return &UnsupportedError{Err: fmt.Errorf("%s is not a readable archive", path.Base(a.path))}
	}
	if err != nil {
		return fmt.Errorf("failed to identify archive format: %w", err)
	}
	a.input = input
	if ex, ok := format.(archiver.Extractor); ok {
		a.extractor = ex
		return nil
	}
	if d, ok := format.(archiver.Decompressor); ok {
		a.decompressor = d
		return nil
	}
	return &UnsupportedError{Err: fmt.Errorf("archive format %T cannot be read", format)}
}

// Close closes the archive file.
func (a *openedArchive) Close() error { return a.file.Close() }

// walk calls visit for every entry of the archive, in archive order, and
// refuses the archive once it passes a limit: too many entries, too deep a
// name, or more bytes declared between them than the total allows. An entry
// whose name climbs out of the archive refuses it too. A zip's directory is
// already in memory, so every entry is checked before the first is visited;
// a streamed format is checked as it goes, so a walk that stops early (to
// serve one entry) has checked only what came before it, which writes
// nothing anywhere. A bare compressed stream is one entry named after the
// archive's stem, of unknown size.
func (a *openedArchive) walk(ctx context.Context, visit func(archiveEntry) error) error {
	count := 0
	var declared int64
	check := func(raw string, e archiveEntry) (string, error) {
		if err := ctx.Err(); err != nil {
			return "", err
		}
		count++
		if count > a.limits.MaxEntries {
			return "", limitError(ArchiveLimitEntries, int64(a.limits.MaxEntries), "")
		}
		name, err := safeEntryName(raw)
		if err != nil {
			return "", err
		}
		if strings.Count(name, "/")+1 > a.limits.MaxDepth {
			return "", limitError(ArchiveLimitDepth, int64(a.limits.MaxDepth), name)
		}
		// Subtracting rather than adding keeps a declared size near
		// MaxInt64 from wrapping the sum round to something small.
		if e.size > 0 {
			if e.size > a.limits.MaxTotalBytes-declared {
				return "", limitError(ArchiveLimitTotalBytes, a.limits.MaxTotalBytes, "")
			}
			declared += e.size
		}
		return name, nil
	}
	visitNamed := func(name string, e archiveEntry) error {
		if name == "" {
			return nil
		}
		e.name = name
		return visit(e)
	}
	counted := func(raw string, e archiveEntry) error {
		name, err := check(raw, e)
		if err != nil {
			return err
		}
		return visitNamed(name, e)
	}

	switch {
	case a.zip != nil:
		names := make([]string, len(a.zip.File))
		for i, f := range a.zip.File {
			name, err := check(f.Name, zipEntry(f))
			if err != nil {
				return err
			}
			names[i] = name
		}
		for i, f := range a.zip.File {
			if err := visitNamed(names[i], zipEntry(f)); err != nil {
				return err
			}
		}
		return nil
	case a.decompressor != nil:
		return counted(storageutil.ArchiveStem(a.path), archiveEntry{
			size: -1,
			open: func() (io.ReadCloser, error) {
				rc, err := a.decompressor.OpenReader(a.input)
				return a.readable(path.Base(a.path), rc, err)
			},
		})
	}
	err := a.extractor.Extract(ctx, a.input, func(_ context.Context, af archiver.FileInfo) error {
		return counted(af.NameInArchive, archiveEntry{
			isDir:  af.IsDir(),
			isLink: af.LinkTarget != "" || af.Mode()&fs.ModeSymlink != 0,
			size:   af.Size(),
			// A tar or rar header has no compressed size of its own.
			modTime: af.ModTime(),
			open: func() (io.ReadCloser, error) {
				rc, err := af.Open()
				return a.readable(af.NameInArchive, rc, err)
			},
		})
	})
	// The extractor prefixes what visit returned with the entry it was on;
	// a typed error already names its entry, and its message is what the
	// client shows, so it comes back as it was made.
	var unsupported *UnsupportedError
	var missing *NotFoundError
	switch {
	case errors.As(err, &unsupported):
		return unsupported
	case errors.As(err, &missing):
		return missing
	}
	return encryptedOr(path.Base(a.path), err)
}

// readable wraps an entry's stream so an encrypted one reads as an
// [EncryptedArchiveError] naming it, whether the format notices on open or
// only on the first read.
func (a *openedArchive) readable(name string, rc io.ReadCloser, err error) (io.ReadCloser, error) {
	if err != nil {
		return nil, encryptedOr(name, err)
	}
	return encryptionAwareReader{ReadCloser: rc, name: name}, nil
}

// encryptionAwareReader reads an entry, reporting a password it needs as an
// [EncryptedArchiveError].
type encryptionAwareReader struct {
	io.ReadCloser
	name string
}

func (r encryptionAwareReader) Read(p []byte) (int, error) {
	n, err := r.ReadCloser.Read(p)
	if err != nil && !errors.Is(err, io.EOF) {
		err = encryptedOr(r.name, err)
	}
	return n, err
}

// encryptedOr turns err into an [EncryptedArchiveError] naming name when it
// says a password is needed, and returns it unchanged otherwise. rardecode
// has sentinels for it; sevenzip has only its AES reader's message, with no
// exported error to match, which is why that one is matched by text.
func encryptedOr(name string, err error) error {
	if err == nil {
		return nil
	}
	if errors.Is(err, rardecode.ErrArchiveEncrypted) ||
		errors.Is(err, rardecode.ErrArchivedFileEncrypted) ||
		errors.Is(err, rardecode.ErrBadPassword) ||
		strings.Contains(err.Error(), "aes7z: no password set") {
		return &UnsupportedError{Err: &EncryptedArchiveError{Name: name}}
	}
	return err
}

// zipEntry describes a zip entry. A size past what an int64 holds is pinned
// to the largest one, so it reads as too big rather than as unknown.
func zipEntry(f *zip.File) archiveEntry {
	return archiveEntry{
		isDir:          f.FileInfo().IsDir(),
		isLink:         f.Mode()&fs.ModeSymlink != 0,
		size:           int64(min(f.UncompressedSize64, math.MaxInt64)),
		compressedSize: int64(min(f.CompressedSize64, math.MaxInt64)),
		modTime:        f.Modified,
		open: func() (io.ReadCloser, error) {
			// Bit 0 of the general purpose flags marks an entry encrypted,
			// ZipCrypto and AES alike; Go's reader would hand back the
			// ciphertext, or a checksum error after it.
			if f.Flags&0x1 != 0 {
				return nil, &UnsupportedError{Err: &EncryptedArchiveError{Name: f.Name}}
			}
			return openZipEntry(f)
		},
	}
}

// safeEntryName is entryName for a name read out of an archive, which refuses
// the archive when the name climbs out of it rather than skipping the entry.
// A backslash counts as a separator for the check, since that is how a
// Windows tool writes "..\x"; a NUL in a name is refused too. A leading
// slash is not climbing out: entryName strips it, so "/etc/passwd" extracts
// to "etc/passwd" inside the folder.
func safeEntryName(raw string) (string, error) {
	if strings.ContainsRune(raw, 0) || climbsOut(raw) || climbsOut(strings.ReplaceAll(raw, `\`, "/")) {
		return "", &UnsupportedError{Err: &UnsafeArchiveEntryError{Entry: raw}}
	}
	return entryName(raw), nil
}

// entryName cleans an entry's name to a slash-separated path with no leading
// or trailing slash. A name that climbs out of the archive ("../x",
// "a/../../x") is "": a requested entry named that way is not found, and a
// name read out of an archive never gets here (safeEntryName).
func entryName(raw string) string {
	p := path.Clean(filepath.ToSlash(raw))
	if p == ".." || strings.HasPrefix(p, "../") {
		return ""
	}
	p = strings.TrimLeft(p, "/")
	if p == "." {
		return ""
	}
	return p
}
