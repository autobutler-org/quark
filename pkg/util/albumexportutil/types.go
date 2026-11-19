package albumexportutil

import "math"

// entry is one file an export copies: the original, where the copy goes
// inside the export folder, and the album paths of the account that hold it.
type entry struct {
	serial  string
	relPath string
	dest    string
	albums  []string
	// outcome is "copied", [ReasonMissing] or [ReasonNotCopied] once the
	// copy has been tried.
	outcome string
}

// photoKey identifies an original across albums: its device and canonical
// path.
type photoKey struct {
	serial  string
	relPath string
}

// manifestHeader names the manifest's columns, in order; the col* constants
// index them.
var manifestHeader = []string{"file", "source_drive", "source_path", "taken", "albums", "result"}

const (
	colFile       = 0
	colSourcePath = 2
	colResult     = 5
)

// libraryLimit lists the whole library in one page.
const libraryLimit = math.MaxInt32

// folderUnsafe are the characters a folder name may not hold on the drives a
// family exports to, FAT and exFAT USB sticks included.
const folderUnsafe = `\/:*?"<>|`
