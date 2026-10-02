package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"mime/multipart"
	"os"
	"path/filepath"
	"time"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
	"github.com/autobutler-org/quark/pkg/vfs"
)

const (
	maxUploads     = 600
	uploadDeadline = 30 * time.Second
)

// uploadLayout is where each upload path lands under the mount: the files
// namespace a multipart upload writes through, the staging directory a
// resumable upload commits from, and a managed device's own data directory.
type uploadLayout struct {
	files, staging, device string
}

func layoutUnder(dir string) uploadLayout {
	return uploadLayout{
		files:   filepath.Join(dir, "files"),
		staging: filepath.Join(dir, "staging"),
		device:  filepath.Join(dir, "device"),
	}
}

// writeUploads lands files through the three ways an upload reaches the disk,
// in turn, until the mount dies under it or it runs out of work.
func writeUploads(ctx context.Context, dir string, l *ledger) error {
	layout := layoutUnder(dir)
	for _, d := range []string{layout.files, layout.staging, filepath.Join(layout.device, "files")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}
	fsys, err := vfs.NewLocalVFS(layout.files, "files")
	if err != nil {
		return err
	}
	device := &storageutil.ManagedDevice{
		DataDir:  layout.device,
		FilesDir: filepath.Join(layout.device, "files"),
	}

	deadline := time.Now().Add(uploadDeadline)
	for i := 0; i < maxUploads && time.Now().Before(deadline); i++ {
		name := uploadName(i)
		var landed string
		switch i % 3 {
		case 0:
			// POST /files/upload into the files namespace.
			landed = filepath.Join("files", name)
			err = fsys.Write(ctx, name, bytes.NewReader(uploadContent(i)), vfs.WriteOptions{IfNoneMatch: "*"})
		case 1:
			// A resumable upload's commit, or a finished transcode.
			landed = filepath.Join("files", name)
			err = stageAndMoveIn(ctx, fsys, layout.staging, name, i)
		default:
			// An upload to a named device.
			landed = filepath.Join("device", "files", name)
			err = uploadToDevice(device, name, i)
		}
		if err != nil {
			return fmt.Errorf("upload %s: %w", landed, err)
		}
		if err := l.ack("upload", landed); err != nil {
			return err
		}
	}
	return nil
}

// stageAndMoveIn writes the file into staging the way a resumable upload
// accumulates chunks, without a flush of its own, and hands it to MoveFileIn.
// Whether the staged bytes reach the disk before the name does is MoveFileIn's
// job, so it is not done for it here.
func stageAndMoveIn(ctx context.Context, fsys *vfs.LocalVFS, staging, name string, i int) error {
	staged, err := os.CreateTemp(staging, "upload-*.part")
	if err != nil {
		return err
	}
	if _, err := staged.Write(uploadContent(i)); err != nil {
		_ = staged.Close()
		return err
	}
	if err := staged.Close(); err != nil {
		return err
	}
	return fsys.MoveFileIn(ctx, staged.Name(), name, vfs.WriteOptions{IfNoneMatch: "*"})
}

// uploadToDevice streams the file through the multipart path an upload to a
// named device takes.
func uploadToDevice(device *storageutil.ManagedDevice, name string, i int) error {
	pr, pw := io.Pipe()
	mw := multipart.NewWriter(pw)
	go func() {
		part, err := mw.CreateFormFile("files", name)
		if err != nil {
			pw.CloseWithError(err)
			return
		}
		if _, err := part.Write(uploadContent(i)); err != nil {
			pw.CloseWithError(err)
			return
		}
		pw.CloseWithError(mw.Close())
	}()
	defer func() { _ = pr.Close() }()

	_, err := storageutil.UploadFilesStreamedImpl(storageutil.UploadFilesStreamedParams{
		Reader: multipart.NewReader(pr, mw.Boundary()),
	}, device, "")
	return err
}

// checkUploads holds what reached the disk to the bar: every acknowledged
// upload is there and whole, and every file a listing would show is whole.
// An upload cut short may be missing, or hidden as a temp; it may never sit
// under its real name holding anything but its full content.
func checkUploads(dir, ledgerPath string) error {
	lines, err := readLedger(ledgerPath)
	if err != nil {
		return err
	}
	var problems []error
	acknowledged := map[string]bool{}
	for _, fields := range lines {
		if len(fields) != 2 || fields[0] != "upload" {
			return fmt.Errorf("malformed ledger line %q", fields)
		}
		acknowledged[fields[1]] = true
		if err := checkUploadedFile(filepath.Join(dir, fields[1])); err != nil {
			problems = append(problems, fmt.Errorf("acknowledged upload %s: %w", fields[1], err))
		}
	}

	visible := 0
	layout := layoutUnder(dir)
	for _, root := range []string{layout.files, filepath.Join(layout.device, "files")} {
		err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			if err != nil || d.IsDir() || storageutil.IsInternalName(d.Name()) {
				return err
			}
			visible++
			rel, _ := filepath.Rel(dir, p)
			if acknowledged[rel] {
				return nil
			}
			if err := checkUploadedFile(p); err != nil {
				problems = append(problems, fmt.Errorf("unacknowledged file %s shown in listings: %w", rel, err))
			}
			return nil
		})
		if err != nil {
			return err
		}
	}

	fmt.Printf("upload: %d acknowledged, %d visible, %d problems\n", len(acknowledged), visible, len(problems))
	return errors.Join(problems...)
}

// checkUploadedFile reports a file that is missing or does not hold exactly
// the content its name promises.
func checkUploadedFile(path string) error {
	var i int
	if _, err := fmt.Sscanf(filepath.Base(path), "file-%05d.bin", &i); err != nil {
		return fmt.Errorf("unexpected name %q", filepath.Base(path))
	}
	got, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if want := uploadContent(i); !bytes.Equal(got, want) {
		return fmt.Errorf("holds %d bytes that are not its content (want %d bytes)", len(got), len(want))
	}
	return nil
}

func uploadName(i int) string {
	return fmt.Sprintf("file-%05d.bin", i)
}

// uploadContent is upload i's bytes: between 1 KiB and 256 KiB, stamped with
// its index, so a file holding another upload's bytes or a torn prefix of its
// own is caught as surely as an empty one.
func uploadContent(i int) []byte {
	size := 1<<10 + (i*7919)%(255<<10)
	unit := []byte(fmt.Sprintf("quark-power-cut-%05d|", i))
	return bytes.Repeat(unit, size/len(unit)+1)[:size]
}
