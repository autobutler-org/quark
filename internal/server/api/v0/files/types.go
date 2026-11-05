package v0_files

import (
	"time"

	"github.com/autobutler-org/quark/pkg/util/serverutil"
)

type router struct{}

func (r *router) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		convertDocumentRoute,
		convertXlsxRoute,
		createDownloadTokenRoute,
		deleteFilesRoute,
		downloadArchiveFileRoute,
		downloadFileRoute,
		exportXlsxRoute,
		extractFileRoute,
		listArchiveRoute,
		listFilesByTypeRoute,
		listFilesRoute,
		listRecentFilesRoute,
		moveFileRoute,
		newFolderRoute,
		searchFilesRoute,
		searchContentRoute,
		statFileRoute,
		uploadFilesRoute,
		uploadFilesNestedRoute,
		createUploadSessionRoute,
		uploadSessionChunkRoute,
		getUploadSessionRoute,
		deleteUploadSessionRoute,
		listUploadSessionsRoute,
	}
}

// slidesRouter holds the PowerPoint export and import routes.
type slidesRouter struct{}

func (r *slidesRouter) Routes() []*serverutil.Route {
	return []*serverutil.Route{
		exportPptxRoute,
		importPptxRoute,
	}
}

// ConvertDocumentJSON reports the .qdoc a document was converted to. The
// client opens Path and shows the warnings: what the .qdoc left out.
type ConvertDocumentJSON struct {
	Path string `json:"path"`
	// Truncated reports a document too long to convert whole; the .qdoc
	// holds its beginning.
	Truncated bool     `json:"truncated"`
	Words     int      `json:"words"`
	Warnings  []string `json:"warnings"`
}

type createDownloadTokenResponse struct {
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expiresAt"`
}

type createUploadSessionRequest struct {
	RootDir   string `json:"rootDir"`
	FileName  string `json:"fileName"`
	TotalSize int64  `json:"totalSize"`
	Serial    string `json:"serial"`
	Overwrite bool   `json:"overwrite"`
	KeepBoth  bool   `json:"keepBoth"`
}

type createUploadSessionResponse struct {
	SessionID string    `json:"sessionId"`
	Offset    int64     `json:"offset"`
	ExpiresAt time.Time `json:"expiresAt"`
}

type uploadSessionStatusResponse struct {
	SessionID string    `json:"sessionId"`
	Offset    int64     `json:"offset"`
	TotalSize int64     `json:"totalSize"`
	FileName  string    `json:"fileName"`
	RootDir   string    `json:"rootDir"`
	ExpiresAt time.Time `json:"expiresAt"`
}

// uploadSessionSummaryResponse is one upload session in
// GET /files/upload-sessions.
type uploadSessionSummaryResponse struct {
	SessionID string `json:"sessionId"`
	FileName  string `json:"fileName"`
	RootDir   string `json:"rootDir"`
	// Serial is the device the file is going to; empty is the internal drive.
	Serial    string `json:"serial"`
	TotalSize int64  `json:"totalSize"`
	// Offset is how many bytes have been committed.
	Offset int64 `json:"offset"`
	// State is uploading or committing for a session in flight, and
	// completed, failed, canceled or expired for one that ended.
	State     string    `json:"state" enums:"uploading,committing,completed,failed,canceled,expired"`
	CreatedAt time.Time `json:"createdAt"`
	// UpdatedAt is when the last chunk landed, or when the session ended.
	UpdatedAt time.Time `json:"updatedAt"`
	// Error is diagnostic text for a failed session, not copy for a user.
	Error string `json:"error"`
}

// listUploadSessionsResponse is the caller's upload sessions: those in
// flight, oldest first, then those that ended, newest first.
type listUploadSessionsResponse struct {
	Active   []uploadSessionSummaryResponse `json:"active"`
	Finished []uploadSessionSummaryResponse `json:"finished"`
}

type moveFileRequest struct {
	OldFilePath     string `json:"oldFilePath"`
	NewFilePath     string `json:"newFilePath"`
	OldDeviceSerial string `json:"oldDeviceSerial"`
	NewDeviceSerial string `json:"newDeviceSerial"`
}

type uploadChunkResponse struct {
	SessionID string `json:"sessionId"`
	Offset    int64  `json:"offset"`
	Complete  bool   `json:"complete"`
	Path      string `json:"path,omitempty"`
}

// uploadFilesResponse lists where each uploaded file landed, files-relative
// and in the order the files arrived, so a client can act on a file that
// keepBoth renamed.
type uploadFilesResponse struct {
	Paths []string `json:"paths"`
}

// uploadFailedResponse answers a batch upload that stopped partway: the
// error, and the files-relative path of each file that landed before it
// (#3533). A client that retries resends only the files not listed, rather
// than landing the listed ones again as keepBoth copies.
type uploadFailedResponse struct {
	Error  string   `json:"error"`
	Landed []string `json:"landed"`
}
