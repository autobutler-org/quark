package derivativeutil

import (
	"errors"
	"fmt"
	"image"
	// Registers the JPEG decoder DecodeConfig validates against.
	_ "image/jpeg"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

// maxEdge is the longest side a derivative of each kind may have: generous
// against the 400 and ~2048 clients send, tight enough to refuse a full-size
// photo passed off as a thumbnail.
func maxEdge(kind Kind) int {
	if kind == KindPreview {
		return 4096
	}
	return 1024
}

// dir is the directory holding the derivatives of the file at source.
func dir(source string) string {
	clean := filepath.Clean(source)
	return filepath.Join(filepath.Dir(clean), DirName, filepath.Base(clean))
}

func store(params StoreParams) (StoreResult, error) {
	if _, ok := ParseKind(string(params.Kind)); !ok {
		return StoreResult{}, fmt.Errorf("%w: unknown kind %q", ErrInvalid, params.Kind)
	}
	target := Path(params.SourcePath, params.Kind)
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return StoreResult{}, fmt.Errorf("create derivative directory: %w", err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(target), "."+string(params.Kind)+"-*.tmp")
	if err != nil {
		return StoreResult{}, fmt.Errorf("create derivative temp file: %w", err)
	}
	tmpPath := tmp.Name()
	committed := false
	defer func() {
		tmp.Close()
		if !committed {
			os.Remove(tmpPath)
		}
	}()

	limit := MaxBytes(params.Kind)
	n, err := io.Copy(tmp, io.LimitReader(params.Reader, limit+1))
	if err != nil {
		return StoreResult{}, fmt.Errorf("write derivative: %w", err)
	}
	if n > limit {
		return StoreResult{}, fmt.Errorf("%w: %s is larger than %d bytes", ErrInvalid, params.Kind, limit)
	}
	if _, err := tmp.Seek(0, io.SeekStart); err != nil {
		return StoreResult{}, fmt.Errorf("rewind derivative: %w", err)
	}
	cfg, format, err := image.DecodeConfig(tmp)
	if err != nil || format != "jpeg" {
		return StoreResult{}, fmt.Errorf("%w: %s is not a JPEG", ErrInvalid, params.Kind)
	}
	if edge := maxEdge(params.Kind); cfg.Width <= 0 || cfg.Height <= 0 || cfg.Width > edge || cfg.Height > edge {
		return StoreResult{}, fmt.Errorf("%w: %s is %dx%d, over %d on a side", ErrInvalid, params.Kind, cfg.Width, cfg.Height, edge)
	}
	if err := tmp.Close(); err != nil {
		return StoreResult{}, fmt.Errorf("close derivative: %w", err)
	}
	if err := os.Rename(tmpPath, target); err != nil {
		return StoreResult{}, fmt.Errorf("commit derivative: %w", err)
	}
	committed = true
	info, err := os.Stat(target)
	if err != nil {
		return StoreResult{}, err
	}
	return StoreResult{Path: target, ModTime: info.ModTime()}, nil
}

func lookup(params LookupParams) (LookupResult, error) {
	target := Path(params.SourcePath, params.Kind)
	info, err := os.Stat(target)
	if errors.Is(err, fs.ErrNotExist) {
		return LookupResult{}, nil
	}
	if err != nil {
		return LookupResult{}, fmt.Errorf("stat derivative: %w", err)
	}
	if info.ModTime().Before(params.SourceModTime) {
		return LookupResult{}, nil
	}
	return LookupResult{Found: true, Path: target, ModTime: info.ModTime()}, nil
}

func move(oldSource, newSource string) error {
	from, to := dir(oldSource), dir(newSource)
	if from == to {
		return nil
	}
	fromInfo, err := os.Lstat(from)
	hasFrom := err == nil
	// A rename that only changes case lands on the same directory on a
	// case-insensitive filesystem; clearing the destination would delete it.
	if toInfo, err := os.Lstat(to); err == nil && (!hasFrom || !os.SameFile(fromInfo, toInfo)) {
		if err := os.RemoveAll(to); err != nil {
			return fmt.Errorf("drop replaced derivatives: %w", err)
		}
		pruneEmpty(filepath.Dir(to))
	}
	if !hasFrom {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(to), 0o755); err != nil {
		return fmt.Errorf("create derivative directory: %w", err)
	}
	if err := os.Rename(from, to); err != nil {
		// Across devices a rename cannot work; the files are small.
		if err := copyDir(from, to); err != nil {
			return err
		}
		if err := os.RemoveAll(from); err != nil {
			return fmt.Errorf("remove moved derivatives: %w", err)
		}
	}
	pruneEmpty(filepath.Dir(from))
	return nil
}

func copyDerivatives(src, dst string) error {
	from, to := dir(src), dir(dst)
	if _, err := os.Lstat(from); errors.Is(err, fs.ErrNotExist) {
		return nil
	}
	if err := os.RemoveAll(to); err != nil {
		return fmt.Errorf("drop replaced derivatives: %w", err)
	}
	return copyDir(from, to)
}

func remove(source string) error {
	d := dir(source)
	if err := os.RemoveAll(d); err != nil {
		return fmt.Errorf("remove derivatives: %w", err)
	}
	pruneEmpty(filepath.Dir(d))
	return nil
}

// copyDir copies the regular files of one derivative directory into another.
// A derivative directory is flat, so nothing deeper is looked at.
func copyDir(from, to string) error {
	entries, err := os.ReadDir(from)
	if err != nil {
		return fmt.Errorf("read derivatives: %w", err)
	}
	if err := os.MkdirAll(to, 0o755); err != nil {
		return fmt.Errorf("create derivative directory: %w", err)
	}
	for _, e := range entries {
		if !e.Type().IsRegular() {
			continue
		}
		if err := copyFile(filepath.Join(from, e.Name()), filepath.Join(to, e.Name())); err != nil {
			return err
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return fmt.Errorf("open derivative: %w", err)
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("create derivative copy: %w", err)
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return fmt.Errorf("copy derivative: %w", err)
	}
	return out.Close()
}

// pruneEmpty removes a folder's derivative directory once nothing is left in
// it, so a folder whose media is all gone is empty again. It fails harmlessly
// while anything remains.
func pruneEmpty(derivativeRoot string) {
	if filepath.Base(derivativeRoot) == DirName {
		_ = os.Remove(derivativeRoot)
	}
}
