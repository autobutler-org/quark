package avatarutil

import (
	"fmt"
	"image"
	"io"
	"io/fs"
	"os"
	"path/filepath"
)

// sniffImage checks that the spooled upload is an image of at most MaxPixels
// and returns the extension its format goes by, rewound for decoding. Only
// the header is read.
func sniffImage(f *os.File) (string, error) {
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return "", fmt.Errorf("rewind upload: %w", err)
	}
	cfg, format, err := image.DecodeConfig(f)
	if err != nil {
		return "", fmt.Errorf("%w: %w", ErrNotImage, err)
	}
	if cfg.Width <= 0 || cfg.Height <= 0 || int64(cfg.Width)*int64(cfg.Height) > MaxPixels {
		return "", fmt.Errorf("%w: %dx%d is too many pixels", ErrNotImage, cfg.Width, cfg.Height)
	}
	if _, err := f.Seek(0, io.SeekStart); err != nil {
		return "", fmt.Errorf("rewind upload: %w", err)
	}
	return "." + format, nil
}

// find returns the path and info of a user's stored picture, or ErrNotFound.
func find(dataDir string, userID int64) (string, fs.FileInfo, error) {
	for _, ext := range []string{".jpg", ".png"} {
		path := filepath.Join(Dir(dataDir), fmt.Sprintf("%d%s", userID, ext))
		info, err := os.Stat(path)
		if err == nil {
			return path, info, nil
		}
		if !os.IsNotExist(err) {
			return "", nil, fmt.Errorf("stat picture: %w", err)
		}
	}
	return "", nil, ErrNotFound
}
