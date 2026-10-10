package photoutil

import (
	"context"
	"errors"
	"fmt"
	"path"

	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// maxCopyNames bounds how many "_copy_<n>" names [CopyPhoto] tries before it
// gives up on finding a free one.
const maxCopyNames = 100

// CopyPhotoParams names the photo to duplicate.
type CopyPhotoParams struct {
	Ctx context.Context
	// Registry holds one namespace per device; the copy is made in Serial's.
	Registry vfs.Registry
	// EventBus hears about the new file. Nil publishes nothing.
	EventBus *eventbus.Bus
	// Serial is the device the photo is on, empty for the internal drive.
	Serial string
	// RelPath is the photo's path on that device.
	RelPath string
}

// CopyPhotoResult is where the copy landed.
type CopyPhotoResult struct {
	// RelPath is the copy's path, beside the original, with no leading slash.
	RelPath string
}

// CopyPhoto duplicates a photo beside the original as "<name>_copy<ext>",
// numbered when that name is taken, through its device's namespace. A copy
// never replaces a file: each name is claimed by the write itself, so two
// copies at once land under two names. A missing photo, or a device with no
// namespace, is [vfs.ErrNotFound].
func CopyPhoto(params CopyPhotoParams) (CopyPhotoResult, error) {
	fsys, err := DeviceFS(params.Registry, params.Serial)
	if err != nil {
		return CopyPhotoResult{}, err
	}
	src := accessutil.Canonical(params.RelPath)
	ext := path.Ext(src)
	stem := src[:len(src)-len(ext)]
	dest := stem + "_copy" + ext
	for i := 2; ; i++ {
		err := fsys.Copy(params.Ctx, src, dest, vfs.CopyOptions{IfNoneMatch: "*"})
		if err == nil {
			break
		}
		if !errors.Is(err, vfs.ErrConflict) {
			return CopyPhotoResult{}, err
		}
		if i > maxCopyNames {
			return CopyPhotoResult{}, fmt.Errorf("no free name for a copy of %s: %w", params.RelPath, err)
		}
		dest = fmt.Sprintf("%s_copy_%d%s", stem, i, ext)
	}
	if params.EventBus != nil {
		params.EventBus.Publish(eventbus.Event{Kind: eventbus.EventUpload, Path: dest, DeviceSerial: params.Serial})
	}
	return CopyPhotoResult{RelPath: dest}, nil
}
