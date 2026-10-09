package trashutil

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

// ctxOf is d's context, or context.Background() when it has none.
func ctxOf(d Device) context.Context {
	if d.Ctx == nil {
		return context.Background()
	}
	return d.Ctx
}

// trasherFor resolves the trash of the device d names. A serial with no
// namespace, or no registry at all, is storageutil.ErrDeviceNotFound, so a
// request for an unplugged drive never lands on another device's trash.
func trasherFor(d Device) (vfs.Trasher, error) {
	var fsys vfs.VFS
	ok := false
	if d.Registry != nil {
		fsys, ok = d.Registry.Get(vfs.FilesNamespace(d.Serial))
	}
	if !ok {
		return nil, fmt.Errorf("%w: %s", storageutil.ErrDeviceNotFound, d.Serial)
	}
	trasher, ok := fsys.(vfs.Trasher)
	if !ok {
		return nil, ErrNoTrash
	}
	return trasher, nil
}

// publishTrashChanged tells open Trash pages to refresh once changed items
// have come or gone. A nil bus is a caller that does not care.
func publishTrashChanged(bus *eventbus.Bus, serial string, changed int) {
	if bus != nil && changed > 0 {
		bus.Publish(eventbus.Event{Kind: eventbus.EventTrashChanged, DeviceSerial: serial})
	}
}

// publishRestored announces restored items the way an uploaded file or a new
// folder is announced, so open file lists, the file index and the content
// indexer all pick them up without learning a new event kind, then that the
// trash changed.
func publishRestored(bus *eventbus.Bus, serial string, restored []vfs.RestoredItem) {
	if bus == nil {
		return
	}
	for _, item := range restored {
		kind := eventbus.EventUpload
		if item.IsDir {
			kind = eventbus.EventNewFolder
		}
		bus.Publish(eventbus.Event{Kind: kind, Path: item.Path, DeviceSerial: serial})
	}
	publishTrashChanged(bus, serial, len(restored))
}

func purgeExpired(params PurgeExpiredParams) (PurgeExpiredResult, error) {
	registry := params.Registry
	if registry == nil {
		return PurgeExpiredResult{}, nil
	}
	ctx := params.Ctx
	if ctx == nil {
		ctx = context.Background()
	}
	now := params.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}

	var result PurgeExpiredResult
	var errs []error
	for _, ns := range registry.List("") {
		serial, ok := vfs.FilesNamespaceSerial(ns.ID)
		if !ok {
			continue
		}
		fsys, ok := registry.Get(ns.ID)
		if !ok {
			continue // unregistered since the listing
		}
		trasher, ok := fsys.(vfs.Trasher)
		if !ok {
			continue
		}
		removed, err := trasher.PurgeExpiredTrash(ctx, now)
		result.Purged += len(removed)
		for _, p := range removed {
			result.Removed = append(result.Removed, Removal{DeviceSerial: serial, Path: p})
		}
		publishTrashChanged(params.EventBus, serial, len(removed))
		if err != nil {
			errs = append(errs, fmt.Errorf("%s: %w", ns.ID, err))
		}
	}
	return result, errors.Join(errs...)
}
