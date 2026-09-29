// Package vaultutil holds the password vault's business logic: entry and
// folder CRUD over the encrypted store, master-password setup, unlock and
// rotation, the importer for CSV/JSON exports from other password managers,
// the plaintext exporter, password generation, and moving the whole vault to
// another device.
//
// The cryptographic primitives live in [github.com/autobutler-org/quark/pkg/util/vaultcrypto]
// and the on-device backup format in [github.com/autobutler-org/quark/pkg/backup];
// vaultutil is the layer that puts those together with the database. HTTP
// concerns — status codes, request binding, response headers — stay with the
// caller, which maps the sentinel errors below onto them.
package vaultutil

import (
	"errors"
	"net/url"
	"strings"
)

// Sentinel errors the caller maps onto a status code. Their text is the copy a
// user reads, so it must not be rewrapped in a way that changes it.
var (
	// ErrEntryNotFound reports a vault entry id with no row behind it.
	ErrEntryNotFound = errors.New("entry not found")
	// ErrFolderNotFound reports a vault folder id with no row behind it.
	ErrFolderNotFound = errors.New("folder not found")
	// ErrVaultNotInitialized reports an unlock against a vault that has never
	// had a master password set.
	ErrVaultNotInitialized = errors.New("vault is not initialized — call POST /vault/setup first")
	// ErrVaultAlreadyInitialized reports a second setup attempt.
	ErrVaultAlreadyInitialized = errors.New("vault is already initialized")
	// ErrIncorrectMasterPassword reports a failed unlock.
	ErrIncorrectMasterPassword = errors.New("incorrect master password")
	// ErrIncorrectCurrentPassword reports a password change whose current
	// password does not match.
	ErrIncorrectCurrentPassword = errors.New("current password is incorrect")
	// ErrMasterPasswordTooShort reports a setup password under the minimum.
	ErrMasterPasswordTooShort = errors.New("master password must be at least 8 characters")
	// ErrNewPasswordTooShort reports a rotation password under the minimum.
	ErrNewPasswordTooShort = errors.New("new password must be at least 8 characters")
	// ErrUnsupportedImportFormat reports an import format the parser has no
	// reader for. The caller names the format in the copy it renders.
	ErrUnsupportedImportFormat = errors.New("unsupported import format")
	// ErrEmptyCharset reports generator options that leave no characters to
	// draw from.
	ErrEmptyCharset = errors.New("no characters available with current settings")
	// ErrBackupImportFailed reports a recovery-backup import the vault
	// rejected — a wrong recovery password, a missing or corrupt backup file.
	// It leads the wrapped message so the copy reads "import failed: ...".
	ErrBackupImportFailed = errors.New("import failed")
	// ErrVaultAlreadyOnDevice reports a migration to the device the vault is
	// already stored on.
	ErrVaultAlreadyOnDevice = errors.New("vault is already on this device")
	// ErrDeviceNotFound reports a target device serial that is not managed or
	// not currently connected. The caller names the serial in its copy.
	ErrDeviceNotFound = errors.New("device not found or not connected")
)

// minPasswordLength is the shortest master password the vault accepts.
const minPasswordLength = 8

// timestampFormat is the wire format for the timestamps the API returns.
const timestampFormat = "2006-01-02T15:04:05Z"

// EntryPayload is the decrypted JSON stored inside vault_entries.ciphertext.
// Everything a user would call secret lives in here; only the name, the URL
// host and the folder are stored in the clear so the list view can be built
// without the key.
type EntryPayload struct {
	URL          string        `json:"url"`
	Username     string        `json:"username"`
	Password     string        `json:"password"`
	Notes        string        `json:"notes,omitempty"`
	TOTPSecret   string        `json:"totpSecret,omitempty"`
	CustomFields []CustomField `json:"customFields,omitempty"`
}

// CustomField is a user-defined name/value pair on an entry.
type CustomField struct {
	Name   string `json:"name"`
	Value  string `json:"value"`
	Hidden bool   `json:"hidden"`
}

// EntryListItem is an entry as it appears in the list view: everything
// readable without the vault key.
type EntryListItem struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	URLHost   string `json:"urlHost"`
	FolderID  *int64 `json:"folderId"`
	CreatedAt string `json:"createdAt"`
	UpdatedAt string `json:"updatedAt"`
}

// EntryDetail is a fully decrypted entry.
type EntryDetail struct {
	ID           int64         `json:"id"`
	Name         string        `json:"name"`
	URL          string        `json:"url"`
	URLHost      string        `json:"urlHost"`
	Username     string        `json:"username"`
	Password     string        `json:"password"`
	Notes        string        `json:"notes,omitempty"`
	TOTPSecret   string        `json:"totpSecret,omitempty"`
	CustomFields []CustomField `json:"customFields,omitempty"`
	FolderID     *int64        `json:"folderId"`
	CreatedAt    string        `json:"createdAt"`
	UpdatedAt    string        `json:"updatedAt"`
}

// Folder is a vault folder as returned to the caller.
type Folder struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	ParentID  *int64 `json:"parentId"`
	SortOrder int64  `json:"sortOrder"`
	CreatedAt string `json:"createdAt"`
}

// EntryFields are the user-supplied fields of an entry, shared by create and
// update because the vault treats an update as a full replacement.
type EntryFields struct {
	Name         string
	URL          string
	Username     string
	Password     string
	Notes        string
	TOTPSecret   string
	CustomFields []CustomField
	FolderID     *int64
}

// FolderFields are the user-supplied fields of a folder.
type FolderFields struct {
	Name      string
	ParentID  *int64
	SortOrder int64
}

// HostFromURL returns the lowercased hostname of a URL, or "" when it is empty
// or unparseable. It is what the vault stores in the clear alongside an entry
// so the list view, and the browser extension's site matching, can tell where
// a login belongs without the key. A URL typed without a scheme ("github.com")
// is read as https, since url.Parse would otherwise take it for a path (#2545).
func HostFromURL(rawURL string) string {
	trimmed := strings.TrimSpace(rawURL)
	if trimmed == "" {
		return ""
	}
	if !strings.Contains(trimmed, "://") {
		trimmed = "https://" + trimmed
	}
	u, err := url.Parse(trimmed)
	if err != nil {
		return ""
	}
	return strings.ToLower(u.Hostname())
}
