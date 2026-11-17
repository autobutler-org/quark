package photoutil

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"

	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// ErrNoMapTile is a tile the Quark's offline tile pack does not hold, or a
// z/x/y that names no tile at all.
var ErrNoMapTile = errors.New("no such map tile")

// MaxMapTileZoom is the deepest zoom level a tile is looked up at, the
// deepest OpenStreetMap's tiles go.
const MaxMapTileZoom = 19

// MapTilesDir is where the Quark's offline map tile pack lives (#3557): a
// standard z/x/y.png tree under the data directory, beside the user's files
// and never among them. The Locations view's map draws from it by default,
// so no third party learns which area is being looked at.
func MapTilesDir() string {
	return filepath.Join(storageutil.GetDataDir(), "maps", "tiles")
}

// OpenMapTileParams names one tile of the pack, as the URL spells it.
type OpenMapTileParams struct {
	// Dir is the tile pack's root; empty means [MapTilesDir].
	Dir     string
	Z, X, Y string
}

// OpenMapTileResult is an open tile. The caller closes Reader.
type OpenMapTileResult struct {
	Reader io.ReadCloser
	Size   int64
}

// OpenMapTile opens one PNG tile of the offline pack. z, x and y must be
// plain decimal numbers naming a tile that exists at that zoom, so nothing
// but a file inside the pack can be named; anything else, or a tile the
// pack lacks, is [ErrNoMapTile].
func OpenMapTile(params OpenMapTileParams) (OpenMapTileResult, error) {
	z, zErr := strconv.Atoi(params.Z)
	x, xErr := strconv.Atoi(params.X)
	y, yErr := strconv.Atoi(params.Y)
	if zErr != nil || xErr != nil || yErr != nil || z < 0 || z > MaxMapTileZoom {
		return OpenMapTileResult{}, ErrNoMapTile
	}
	if side := 1 << z; x < 0 || y < 0 || x >= side || y >= side {
		return OpenMapTileResult{}, ErrNoMapTile
	}
	dir := params.Dir
	if dir == "" {
		dir = MapTilesDir()
	}
	path := filepath.Join(dir, strconv.Itoa(z), strconv.Itoa(x), strconv.Itoa(y)+".png")
	f, err := os.Open(path)
	if err != nil {
		if storageutil.IsNotExist(err) {
			return OpenMapTileResult{}, ErrNoMapTile
		}
		return OpenMapTileResult{}, fmt.Errorf("open map tile: %w", err)
	}
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() {
		_ = f.Close()
		return OpenMapTileResult{}, ErrNoMapTile
	}
	return OpenMapTileResult{Reader: f, Size: info.Size()}, nil
}
