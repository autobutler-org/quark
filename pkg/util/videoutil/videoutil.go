// Package videoutil probes, trims, and remuxes video files with sprocket, in
// pure Go: none of the three decodes a frame, so they work for every codec and
// need nothing installed on the device. A video is read through the VFS
// (OpenSource) and a clip written through it (TrimFile), so neither touches a
// host path.
//
// Keyframe is the one that decodes, for video thumbnails, and it is pure Go
// too. sprocket carries a decoder for AV1 and VP8 only, so every other codec
// answers ErrNoDecoder and is left for a client to render.
package videoutil

import (
	"context"
	"errors"
	"fmt"
	"image"
	"io"
	"os"
	"path"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/autobutler-org/sprocket/pkg/sprocket"
)

// VideoInfo is what Probe reports about a video file.
type VideoInfo struct {
	Duration time.Duration
	Width    int
	Height   int
	// VideoCodec and AudioCodec use ffprobe's names ("h264", "ac3", "flac"),
	// which is what the API has always returned.
	VideoCodec string
	AudioCodec string
	Bitrate    int64
	Framerate  float64
	// Rotation is in degrees (0, 90, 180, 270) counterclockwise, ffprobe's
	// display-matrix convention: a phone's portrait video reports 270.
	Rotation int
}

// Format is a video container Remux writes, named by its file extension
// without the dot, such as "mp4" or "mkv".
type Format string

var (
	// ErrCannotTrim is returned by Trim for a source it cannot cut on the
	// device: an MPEG-TS file, or a fragmented MP4.
	ErrCannotTrim = errors.New("this video's container can't be trimmed")
	// ErrNotAVideo is returned for a file that does not parse as a video.
	ErrNotAVideo = errors.New("not a readable video")
	// ErrStartPastEnd is returned by TrimFile for a start at or past the end of
	// the video.
	ErrStartPastEnd = errors.New("start is at or past the end of the video")
	// ErrNoFreeName is returned by PlaceUnderFreeName when every name it tried
	// was taken.
	ErrNoFreeName = errors.New("no free name for the new file")
)

// ErrNoDecoder is returned by Keyframe for a video whose codec the device has
// no decoder for, which is every one but AV1 and VP8, and for a frame over the
// decoder's size cap. The file is fine; the device just cannot picture it.
var ErrNoDecoder = errors.New("this video's codec can't be decoded on the device")

// Formats returns every Format Remux writes, in the order clients list them.
func Formats() []Format {
	formats := make([]Format, 0, len(formatSpecs))
	for _, spec := range formatSpecs {
		formats = append(formats, Format(spec.container))
	}
	return formats
}

// Valid reports whether f is a Format Remux writes.
func (f Format) Valid() bool {
	_, ok := lookupFormat(f)
	return ok
}

// Label is f's display name, such as "MP4" or "WebM", and "" for a Format
// that is not Valid.
func (f Format) Label() string {
	spec, _ := lookupFormat(f)
	return spec.label
}

// Source is a video to read: its bytes, read at any offset, its size, and its
// name, whose extension names its container. OpenSource opens one in a VFS
// namespace; a test or a caller holding a host file builds one from an
// *os.File.
type Source struct {
	File    vfs.File
	Size    int64
	Name    string
	ModTime time.Time
}

// Close closes the Source's file.
func (s Source) Close() error {
	return s.File.Close()
}

// OpenSourceParams names a video in a namespace.
type OpenSourceParams struct {
	FS   vfs.VFS
	Path string
}

// OpenSource opens the video at Path in FS. Its errors are the VFS's: a missing
// path is vfs.ErrNotFound, one escaping the namespace vfs.ErrPermissionDenied,
// and a folder vfs.ErrIsDirectory. The caller closes the Source.
func OpenSource(ctx context.Context, params OpenSourceParams) (Source, error) {
	info, err := params.FS.Stat(ctx, params.Path)
	if err != nil {
		return Source{}, err
	}
	if info.IsDir {
		return Source{}, vfs.ErrIsDirectory
	}
	f, err := params.FS.Open(ctx, params.Path)
	if err != nil {
		return Source{}, err
	}
	return Source{File: f, Size: info.Size, Name: path.Base(info.Path), ModTime: info.ModTime}, nil
}

// Probe reports on the video at the host path filePath, as ProbeSource does.
// It is for the thumbnail generator, which holds a host path as Keyframe
// does; everything reading a user's video opens it with OpenSource and calls
// ProbeSource.
func Probe(ctx context.Context, filePath string) (*VideoInfo, error) {
	f, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil {
		return nil, err
	}
	return ProbeSource(ctx, Source{File: f, Size: stat.Size(), Name: filepath.Base(filePath), ModTime: stat.ModTime()})
}

// ProbeSource reports the duration, dimensions, codecs, bitrate, framerate,
// and rotation of src. It reads headers only. ctx is accepted for the callers'
// sake; a probe costs a few reads and cannot be interrupted. A file that does
// not parse as a video is ErrNotAVideo.
func ProbeSource(_ context.Context, src Source) (*VideoInfo, error) {
	info, err := probe(src)
	if err != nil {
		return nil, err
	}
	return &VideoInfo{
		Duration:   info.Duration,
		Width:      info.Width,
		Height:     info.Height,
		VideoCodec: ffprobeCodecName(info.VideoCodec),
		AudioCodec: ffprobeCodecName(info.AudioCodec),
		Bitrate:    int64(info.Bitrate),
		Framerate:  info.FrameRate,
		Rotation:   counterclockwise(info.Rotation),
	}, nil
}

// Targets returns the Formats src can be remuxed into, in Formats order: every
// one sprocket.CanRemux allows for its codecs and its container family,
// leaving out its own format, which would only copy the file. Remux reads the
// same table. A file that does not parse as a video is ErrNotAVideo.
func Targets(src Source) ([]Format, error) {
	info, err := probe(src)
	if err != nil {
		return nil, err
	}
	own := formatOf(src.Name)
	targets := []Format{}
	for _, spec := range formatSpecs {
		if Format(spec.container) != own && sprocket.CanRemux(info, spec.container) {
			targets = append(targets, Format(spec.container))
		}
	}
	return targets, nil
}

// TrimFormat is the Format Trim writes the source at path into: its own when
// Remux writes it, and MP4 otherwise.
func TrimFormat(path string) Format {
	if own := formatOf(path); own.Valid() {
		return own
	}
	return "mp4"
}

// TrimParams describes one Trim.
type TrimParams struct {
	Source Source
	// Output receives the clip. A failed trim may have written part of one,
	// so it goes somewhere nothing lists until it is complete: VFS.Write's
	// atomic write, which TrimFile uses.
	Output     io.Writer
	Start, End time.Duration
}

// TrimResult is what a Trim produced.
type TrimResult struct {
	// Start is where the output is shown from on the source's timeline. It is
	// the requested start, with the frames back to the keyframe before it kept
	// but hidden, except where sprocket has nothing to hide them behind or
	// nothing to hide: a TS output, which shows them and reports the keyframe,
	// or a start before the first keyframe or past the last video frame, which
	// takes that keyframe.
	Start time.Duration
}

// Trim copies [Start, End) of Source into Output, in TrimFormat of its name,
// without re-encoding. It stops with ctx's error when ctx is done. The result
// reports where the output is shown from. A source it cannot cut returns
// ErrCannotTrim.
func Trim(ctx context.Context, params TrimParams) (TrimResult, error) {
	src := params.Source
	w := &progressWriter{ctx: ctx, w: params.Output, total: src.Size}
	start, err := sprocket.Trim(src.File, src.Size, w, sprocket.Container(TrimFormat(src.Name)), params.Start, params.End)
	if errors.Is(err, sprocket.ErrUnsupportedContainer) || errors.Is(err, sprocket.ErrIncompatible) {
		return TrimResult{}, fmt.Errorf("%w: %w", ErrCannotTrim, err)
	}
	if err != nil {
		return TrimResult{}, err
	}
	return TrimResult{Start: start}, nil
}

// TrimFileParams describes a trim of a video in a namespace into a new file
// beside it.
type TrimFileParams struct {
	FS vfs.VFS
	// Path is the source video's path in FS.
	Path string
	// Start must fall before the end of the video. An End at or past it keeps
	// the rest of the video.
	Start, End time.Duration
}

// TrimFileResult is the clip a TrimFile wrote.
type TrimFileResult struct {
	// Path is the clip's path in FS.
	Path string
	// Start is TrimResult.Start.
	Start time.Duration
}

// TrimFile trims the video at Path into "<stem>_trimmed.<TrimFormat>" beside
// it, or the first numbered name after that nothing has. The clip is written
// through FS.Write, so it never exists under its name until it is whole, and
// with IfNoneMatch "*", so it never replaces a file. Besides OpenSource's
// errors it returns ErrNotAVideo, ErrStartPastEnd, ErrCannotTrim, and
// ErrNoFreeName.
func TrimFile(ctx context.Context, params TrimFileParams) (TrimFileResult, error) {
	src, err := OpenSource(ctx, OpenSourceParams{FS: params.FS, Path: params.Path})
	if err != nil {
		return TrimFileResult{}, err
	}
	defer src.Close()
	info, err := ProbeSource(ctx, src)
	if err != nil {
		return TrimFileResult{}, err
	}
	// The client picks End from its player's duration, which is not this
	// probe's and can land a millisecond past it.
	if params.Start >= info.Duration {
		return TrimFileResult{}, fmt.Errorf("%w: start %d ms, video %d ms",
			ErrStartPastEnd, params.Start.Milliseconds(), info.Duration.Milliseconds())
	}
	end := min(params.End, info.Duration)

	var result TrimResult
	out, err := PlaceUnderFreeName(PlaceUnderFreeNameParams{
		Dir:  path.Dir(cleanPath(params.Path)),
		Name: trimmedName(src.Name),
		Place: func(p string) error {
			result, err = writeTrim(ctx, params.FS, p, TrimParams{Source: src, Start: params.Start, End: end})
			return err
		},
	})
	if err != nil {
		return TrimFileResult{}, err
	}
	return TrimFileResult{Path: out, Start: result.Start}, nil
}

// RemuxParams describes one Remux.
type RemuxParams struct {
	// Source is the video to read.
	Source Source
	// Output receives the result. A failed remux may have written part of
	// one, so it goes somewhere nothing lists until it is complete.
	Output io.Writer
	Format Format
	// OnProgress, when non-nil, is called with the fraction of the source
	// written so far, in [0, 1], from the goroutine running Remux.
	OnProgress func(fraction float64)
}

// Remux copies Source's video and audio streams into Output as Format without
// re-encoding them. It stops with ctx's error when ctx is done. A source whose
// codecs Format cannot hold is refused; Targets names the formats that fit.
func Remux(ctx context.Context, params RemuxParams) error {
	if !params.Format.Valid() {
		return fmt.Errorf("unknown remux format %q", params.Format)
	}
	src := params.Source
	w := &progressWriter{ctx: ctx, w: params.Output, total: src.Size, onProgress: params.OnProgress}
	return sprocket.Remux(src.File, src.Size, w, sprocket.Container(params.Format))
}

// PlaceUnderFreeNameParams describes a new file landing in a folder.
type PlaceUnderFreeNameParams struct {
	// Dir is the folder's path in the namespace.
	Dir string
	// Name is the name the file would like: "clip.mp4".
	Name string
	// Place puts the file at a path, answering vfs.ErrConflict when something
	// is already there. It is called again for every name it is refused.
	Place func(path string) error
}

// PlaceUnderFreeName lands a new file under Name in Dir, or under the first of
// Name's numbered names ("clip_(1).mp4", "clip_(2).mp4", ...) that Place does
// not refuse with vfs.ErrConflict, and returns the path it landed at. The
// name is never checked ahead of Place, so a file appearing at it at any
// moment costs one more attempt rather than an overwrite. After
// maxFreeNameAttempts refusals it gives up with ErrNoFreeName.
func PlaceUnderFreeName(params PlaceUnderFreeNameParams) (string, error) {
	for n := range maxFreeNameAttempts {
		p := path.Join(params.Dir, storageutil.NumberedName(params.Name, n))
		err := params.Place(p)
		if !errors.Is(err, vfs.ErrConflict) {
			return p, err
		}
	}
	return "", fmt.Errorf("%w: %s", ErrNoFreeName, params.Name)
}

// KeyframeParams describes one Keyframe.
type KeyframeParams struct {
	// Source is the video to read.
	Source string
	// At is the time the keyframe is taken nearest to.
	At time.Duration
}

// KeyframeResult is what a Keyframe decoded.
type KeyframeResult struct {
	// Image is the keyframe at its own size, the way up a player shows it:
	// the rotation an MP4 track carries is already applied.
	Image image.Image
}

// Keyframe decodes the keyframe of Source nearest At, without running
// anything outside the process. It reads that one sample rather than the
// file, and holds one decoded frame. A time past the end takes the last
// keyframe. A codec with no decoder returns ErrNoDecoder.
func Keyframe(params KeyframeParams) (KeyframeResult, error) {
	src, err := os.Open(params.Source)
	if err != nil {
		return KeyframeResult{}, err
	}
	defer src.Close()
	stat, err := src.Stat()
	if err != nil {
		return KeyframeResult{}, err
	}
	frame, err := sprocket.Thumbnail(src, stat.Size(), params.At, sprocket.ThumbnailOptions{})
	if errors.Is(err, sprocket.ErrUnsupportedCodec) {
		return KeyframeResult{}, fmt.Errorf("%w: %w", ErrNoDecoder, err)
	}
	if err != nil {
		return KeyframeResult{}, fmt.Errorf("keyframe of %s: %w", filepath.Base(params.Source), err)
	}
	return KeyframeResult{Image: frame.Image}, nil
}
