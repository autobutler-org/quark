package chatutil

import (
	"bytes"
	"context"
	"database/sql"
	"errors"
	"io"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/accessutil"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

// MaxAttachmentBytes is the most ciphertext one attachment may store. It is a
// disk cap, not a limit on decrypting: a client opens one chunk at a time.
const MaxAttachmentBytes int64 = 4 << 30

// MaxAttachmentsPerMessage is how many files one message may name.
const MaxAttachmentsPerMessage = 10

const unboundAttachmentMaxAge = 24 * time.Hour

var (
	// ErrInvalidAttachment reports an id that is not 64 lowercase hex
	// characters. Such an id is refused before it is used as a path.
	ErrInvalidAttachment = errors.New("an attachment id is 64 lowercase hex characters")
	// ErrCannotAttach reports a reader without attach_files.
	ErrCannotAttach = errors.New("you can't attach files in this channel")
	// ErrAttachmentTooLarge reports ciphertext over MaxAttachmentBytes.
	ErrAttachmentTooLarge = errors.New("an attachment can be at most 4 GiB")
	// ErrAttachmentExists reports an id that already names an attachment.
	ErrAttachmentExists = errors.New("an attachment with that id already exists")
	// ErrAttachmentNotFound reports an attachment the caller cannot read,
	// including one that does not exist.
	ErrAttachmentNotFound = errors.New("no attachment has that id")
	// ErrTooManyAttachments reports a post naming more than
	// MaxAttachmentsPerMessage files.
	ErrTooManyAttachments = errors.New("a message can name at most 10 attachments")
)

// PutAttachmentParams stores one attachment's ciphertext.
type PutAttachmentParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	ChannelID int64
	// ID is 64 lowercase hex characters, chosen by the client.
	ID string
	// DataDir is the Quark's data directory (storageutil.GetDataDir).
	DataDir string
	// Body is the ciphertext. It is streamed to disk and not buffered.
	Body io.Reader
}

// PutAttachmentResult is the attachment as stored.
type PutAttachmentResult struct {
	ID       string `json:"id"`
	ByteSize int64  `json:"byteSize"`
}

// PutAttachment stores ciphertext for a member who holds attach_files.
// Anyone without read_messages gets ErrChannelNotFound, a reader without
// attach_files gets ErrCannotAttach, a bad id gets ErrInvalidAttachment, and
// an id already stored gets ErrAttachmentExists. Ciphertext over
// MaxAttachmentBytes is ErrAttachmentTooLarge. Unbound attachments older than
// a day are swept first; a sweep that fails is logged and the upload still
// proceeds. Nothing is published: the bytes are not a message yet.
func PutAttachment(params PutAttachmentParams) (PutAttachmentResult, error) {
	path, err := attachmentPath(params.DataDir, params.ChannelID, params.ID)
	if err != nil {
		return PutAttachmentResult{}, err
	}
	if params.Database == nil {
		return PutAttachmentResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	perms, err := memberPerms(params.Ctx, queries, params.Principal, params.ChannelID)
	if err != nil {
		return PutAttachmentResult{}, err
	}
	if !perms.Has(PermAttachFiles) {
		return PutAttachmentResult{}, ErrCannotAttach
	}
	sweepUnboundAttachments(params.Ctx, queries, params.DataDir)
	_, err = queries.GetChatAttachment(params.Ctx, params.ID)
	if err == nil {
		return PutAttachmentResult{}, ErrAttachmentExists
	}
	if !errors.Is(err, sql.ErrNoRows) {
		return PutAttachmentResult{}, err
	}
	body := params.Body
	if body == nil {
		body = bytes.NewReader(nil)
	}
	n, err := writeAttachment(path, body)
	if err != nil {
		return PutAttachmentResult{}, err
	}
	row, err := queries.CreateChatAttachment(params.Ctx, db.CreateChatAttachmentParams{
		ID: params.ID, ChannelID: params.ChannelID, UploaderID: params.Principal.UserID, ByteSize: n,
	})
	if err != nil {
		if rmErr := os.Remove(path); rmErr != nil && !errors.Is(rmErr, os.ErrNotExist) {
			log.Printf("chat: attachment %s was not recorded and its file could not be removed: %v", params.ID, rmErr)
		}
		if sqlutil.IsUniqueConstraintErr(err) {
			return PutAttachmentResult{}, ErrAttachmentExists
		}
		return PutAttachmentResult{}, err
	}
	return PutAttachmentResult{ID: row.ID, ByteSize: n}, nil
}

// OpenAttachmentParams reads one attachment's ciphertext.
type OpenAttachmentParams struct {
	Ctx       context.Context
	Database  *db.DatabaseSqlc
	Principal accessutil.Principal
	ChannelID int64
	ID        string
	// DataDir is the Quark's data directory (storageutil.GetDataDir).
	DataDir string
}

// OpenAttachmentResult is the ciphertext file. The caller closes File.
type OpenAttachmentResult struct {
	File     *os.File
	ByteSize int64
}

// OpenAttachment opens an attachment's ciphertext. A missing row, a row in
// another channel, a file missing on disk, and an unbound attachment opened
// by anyone but its uploader are ErrAttachmentNotFound, so the answer does
// not reveal that the id exists. A bound attachment needs read_messages;
// delegated managers and admins without it get ErrAttachmentNotFound too.
func OpenAttachment(params OpenAttachmentParams) (OpenAttachmentResult, error) {
	path, err := attachmentPath(params.DataDir, params.ChannelID, params.ID)
	if err != nil {
		return OpenAttachmentResult{}, err
	}
	if params.Database == nil {
		return OpenAttachmentResult{}, accessutil.ErrNoDatabase
	}
	queries := params.Database.Queries
	row, err := queries.GetChatAttachment(params.Ctx, params.ID)
	if errors.Is(err, sql.ErrNoRows) {
		return OpenAttachmentResult{}, ErrAttachmentNotFound
	}
	if err != nil {
		return OpenAttachmentResult{}, err
	}
	if row.ChannelID != params.ChannelID {
		return OpenAttachmentResult{}, ErrAttachmentNotFound
	}
	if !row.MessageID.Valid {
		if row.UploaderID != params.Principal.UserID {
			return OpenAttachmentResult{}, ErrAttachmentNotFound
		}
	} else if _, err := memberPerms(params.Ctx, queries, params.Principal, params.ChannelID); err != nil {
		if errors.Is(err, ErrChannelNotFound) {
			return OpenAttachmentResult{}, ErrAttachmentNotFound
		}
		return OpenAttachmentResult{}, err
	}
	file, err := os.Open(path)
	if errors.Is(err, os.ErrNotExist) {
		return OpenAttachmentResult{}, ErrAttachmentNotFound
	}
	if err != nil {
		return OpenAttachmentResult{}, err
	}
	return OpenAttachmentResult{File: file, ByteSize: row.ByteSize}, nil
}

// RemoveChannelAttachmentFilesParams names the files a deleted channel held.
type RemoveChannelAttachmentFilesParams struct {
	DataDir   string
	ChannelID int64
	IDs       []string
}

// RemoveChannelAttachmentFiles removes each attachment file, then the channel
// directory when nothing else is left in it. A file that is already gone is
// not an error.
func RemoveChannelAttachmentFiles(params RemoveChannelAttachmentFilesParams) error {
	if params.DataDir == "" {
		return errors.New("chat attachments need a data directory")
	}
	for _, id := range params.IDs {
		if err := removeAttachment(params.DataDir, params.ChannelID, id); err != nil {
			return err
		}
	}
	return removeEmptyDir(channelAttachmentDir(params.DataDir, params.ChannelID))
}

// AttachmentPath is the ciphertext file for an attachment, after the id has
// been checked. A bad id is ErrInvalidAttachment and no path is returned.
func AttachmentPath(dataDir string, channelID int64, id string) (string, error) {
	return attachmentPath(dataDir, channelID, id)
}

func attachmentPath(dataDir string, channelID int64, id string) (string, error) {
	if !validAttachmentID(id) {
		return "", ErrInvalidAttachment
	}
	if dataDir == "" {
		return "", errors.New("chat attachments need a data directory")
	}
	return filepath.Join(channelAttachmentDir(dataDir, channelID), id), nil
}

func channelAttachmentDir(dataDir string, channelID int64) string {
	return filepath.Join(dataDir, "chat-attachments", strconv.FormatInt(channelID, 10))
}

func validateAttachmentIDs(ids []string) error {
	if len(ids) > MaxAttachmentsPerMessage {
		return ErrTooManyAttachments
	}
	for _, id := range ids {
		if !validAttachmentID(id) {
			return ErrInvalidAttachment
		}
	}
	return nil
}

// bindMessageAttachments claims each id for messageID. Zero rows changed is
// ErrAttachmentNotFound, and the caller's transaction rolls the message back
// with it. A unique violation must not reach here: the insert that raised it
// has already ended the transaction.
func bindMessageAttachments(ctx context.Context, queries db.Querier, params PostMessageParams, messageID int64) error {
	for _, id := range params.AttachmentIDs {
		n, err := queries.BindChatAttachment(ctx, db.BindChatAttachmentParams{
			MessageID:  sql.NullInt64{Int64: messageID, Valid: true},
			ID:         id,
			ChannelID:  params.ChannelID,
			UploaderID: params.Principal.UserID,
		})
		if err != nil {
			return err
		}
		if n != 1 {
			return ErrAttachmentNotFound
		}
	}
	return nil
}

// repeatedAttachments reports whether a retry's ids are already bound to
// message by the caller in that channel. Bound to any other message, or not
// the caller's, is ErrAttachmentNotFound. A missing row is the same, unless
// message was deleted: its attachment rows were removed with the tombstone,
// and the retry still returns that tombstone.
func repeatedAttachments(ctx context.Context, queries db.Querier, params PostMessageParams, message Message) error {
	for _, id := range params.AttachmentIDs {
		row, err := queries.GetChatAttachment(ctx, id)
		if errors.Is(err, sql.ErrNoRows) {
			if message.DeletedAt != nil {
				continue
			}
			return ErrAttachmentNotFound
		}
		if err != nil {
			return err
		}
		if row.ChannelID != params.ChannelID || row.UploaderID != params.Principal.UserID ||
			!row.MessageID.Valid || row.MessageID.Int64 != message.ID {
			return ErrAttachmentNotFound
		}
	}
	return nil
}

func validAttachmentID(id string) bool {
	if len(id) != 64 {
		return false
	}
	for i := 0; i < len(id); i++ {
		c := id[i]
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

func sweepUnboundAttachments(ctx context.Context, queries db.Querier, dataDir string) {
	cutoff := time.Now().Add(-unboundAttachmentMaxAge).UTC()
	rows, err := queries.ListUnboundChatAttachmentsBefore(ctx, cutoff)
	if err != nil {
		log.Printf("chat: list unbound attachments: %v", err)
		return
	}
	if err := queries.DeleteUnboundChatAttachmentsBefore(ctx, cutoff); err != nil {
		log.Printf("chat: delete unbound attachments: %v", err)
		return
	}
	for _, row := range rows {
		if err := removeAttachment(dataDir, row.ChannelID, row.ID); err != nil {
			log.Printf("chat: remove unbound attachment %s: %v", row.ID, err)
		}
	}
}

func writeAttachment(path string, r io.Reader) (int64, error) {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return 0, err
	}
	// A private temp name, then a link onto the final path. The link fails
	// when the path exists, so two uploads of one id cannot overwrite each
	// other. The temp name is removed either way; the linked file stays.
	file, err := os.CreateTemp(dir, ".attachment-*")
	if err != nil {
		return 0, err
	}
	part := file.Name()
	defer func() { _ = os.Remove(part) }()
	n, err := io.Copy(file, io.LimitReader(r, MaxAttachmentBytes+1))
	if err != nil {
		_ = file.Close()
		return 0, err
	}
	if n > MaxAttachmentBytes {
		_ = file.Close()
		return 0, ErrAttachmentTooLarge
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return 0, err
	}
	if err := file.Close(); err != nil {
		return 0, err
	}
	if err := os.Link(part, path); err != nil {
		if errors.Is(err, os.ErrExist) {
			return 0, ErrAttachmentExists
		}
		return 0, err
	}
	return n, nil
}

func removeAttachment(dataDir string, channelID int64, id string) error {
	path, err := attachmentPath(dataDir, channelID, id)
	if err != nil {
		return err
	}
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return nil
}

func removeEmptyDir(dir string) error {
	err := os.Remove(dir)
	if err == nil || errors.Is(err, os.ErrNotExist) || errors.Is(err, syscall.ENOTEMPTY) {
		return nil
	}
	return err
}
