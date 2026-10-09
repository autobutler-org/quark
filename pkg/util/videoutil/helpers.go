package videoutil

import (
	"cmp"
	"context"
	"errors"
	"fmt"
	"io"
	"path"
	"path/filepath"
	"slices"
	"strings"

	"github.com/autobutler-org/quark/pkg/vfs"
	"github.com/autobutler-org/sprocket/pkg/sprocket"
)

// probe runs sprocket's Probe over src. A file it cannot parse is
// ErrNotAVideo.
func probe(src Source) (sprocket.Info, error) {
	info, err := sprocket.Probe(src.File, src.Size)
	if err != nil {
		return sprocket.Info{}, fmt.Errorf("%w: probe %s: %w", ErrNotAVideo, src.Name, err)
	}
	return info, nil
}

// writeTrim runs one Trim into a new file at p in fsys. The clip streams into
// fsys.Write through a pipe, so it is never buffered and never visible at p
// until it is whole. A name already taken is vfs.ErrConflict, and Write
// refuses most before reading a byte, so trying the next name costs nothing.
func writeTrim(ctx context.Context, fsys vfs.VFS, p string, params TrimParams) (TrimResult, error) {
	pr, pw := io.Pipe()
	done := make(chan error, 1)
	var result TrimResult
	go func() {
		params.Output = pw
		var err error
		result, err = Trim(ctx, params)
		// A nil error ends the write with EOF; anything else fails it.
		_ = pw.CloseWithError(err)
		done <- err
	}()
	writeErr := fsys.Write(ctx, p, pr, vfs.WriteOptions{IfNoneMatch: "*"})
	// A Write that stopped reading early leaves the trim blocked on the pipe.
	_ = pr.CloseWithError(cmp.Or(writeErr, io.ErrClosedPipe))
	trimErr := <-done
	switch {
	case errors.Is(writeErr, vfs.ErrConflict):
		return TrimResult{}, writeErr
	case trimErr != nil:
		return TrimResult{}, trimErr
	case writeErr != nil:
		return TrimResult{}, writeErr
	}
	return result, nil
}

// trimmedName is the name TrimFile wants for a clip of the video named name:
// "clip_trimmed.mov", or "clip_trimmed.mp4" for a container Trim does not
// keep.
func trimmedName(name string) string {
	ext := filepath.Ext(name)
	stem := strings.TrimSuffix(name, ext)
	if format := "." + string(TrimFormat(name)); !strings.EqualFold(ext, format) {
		ext = format
	}
	return stem + "_trimmed" + ext
}

// cleanPath is a namespace path in the form the VFS reports one: slashes,
// no leading slash, and "" for the root.
func cleanPath(p string) string {
	return strings.TrimPrefix(path.Clean("/"+filepath.ToSlash(p)), "/")
}

// lookupFormat finds f's row in formatSpecs.
func lookupFormat(f Format) (formatSpec, bool) {
	i := slices.IndexFunc(formatSpecs, func(spec formatSpec) bool { return Format(spec.container) == f })
	if i < 0 {
		return formatSpec{}, false
	}
	return formatSpecs[i], true
}

// formatOf is the Format path's extension names, which may not be Valid.
func formatOf(path string) Format {
	return Format(strings.ToLower(strings.TrimPrefix(filepath.Ext(path), ".")))
}

// ffprobeCodecName translates a sprocket codec name into ffprobe's.
func ffprobeCodecName(name string) string {
	if mapped, ok := ffprobeCodecNames[name]; ok {
		return mapped
	}
	return name
}

// counterclockwise turns sprocket's clockwise rotation into the
// counterclockwise degrees ffprobe's display matrix reports, normalized to
// [0, 360): a phone's portrait video is 90 in one and 270 in the other.
func counterclockwise(clockwise int) int {
	return (360 - clockwise%360) % 360
}
