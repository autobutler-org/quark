package vaultutil

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
)

// ListEntriesParams lists the vault's entries. No key is needed: the list view
// is built entirely from the columns stored in the clear.
type ListEntriesParams struct {
	Queries *db.Queries
}

// ListEntriesResult carries the entries in storage order.
type ListEntriesResult struct {
	Entries []EntryListItem
}

// GetEntryParams reads and decrypts one entry.
type GetEntryParams struct {
	Queries *db.Queries
	// Key is the unlocked vault key. The caller still owns it and is
	// responsible for zeroing it.
	Key []byte
	ID  int64
}

// GetEntryResult carries the decrypted entry.
type GetEntryResult struct {
	Entry EntryDetail
}

// BackfillEntryHostsParams recomputes url_host for entries stored with an empty
// one, which the key is needed for because the URL itself is encrypted.
type BackfillEntryHostsParams struct {
	Queries *db.Queries
	Key     []byte
}

// BackfillEntryHostsResult counts the entries whose host was filled in.
type BackfillEntryHostsResult struct {
	Updated int
}

// CreateEntryParams encrypts a new entry and stores it.
type CreateEntryParams struct {
	Queries *db.Queries
	Key     []byte
	Fields  EntryFields
}

// CreateEntryResult carries the stored entry, decrypted fields included, so
// the caller can echo it back without a second read.
type CreateEntryResult struct {
	Entry EntryDetail
}

// UpdateEntryParams replaces an existing entry wholesale.
type UpdateEntryParams struct {
	Queries *db.Queries
	Key     []byte
	ID      int64
	Fields  EntryFields
}

// UpdateEntryResult carries the id of the entry that was replaced.
type UpdateEntryResult struct {
	ID int64
}

// DeleteEntryParams removes one entry.
type DeleteEntryParams struct {
	Queries *db.Queries
	ID      int64
}

// DeleteEntryResult reports the deletion. Deleting an id that is already gone
// is not an error, matching the underlying DELETE.
type DeleteEntryResult struct {
	Deleted bool
}

// ListEntries returns every entry's clear-text metadata.
func ListEntries(ctx context.Context, params ListEntriesParams) (ListEntriesResult, error) {
	rows, err := params.Queries.ListVaultEntries(ctx)
	if err != nil {
		return ListEntriesResult{}, fmt.Errorf("list entries: %w", err)
	}

	items := make([]EntryListItem, 0, len(rows))
	for _, r := range rows {
		items = append(items, EntryListItem{
			ID:        r.ID,
			Name:      r.Name,
			URLHost:   r.UrlHost,
			FolderID:  fromNullInt64(r.FolderID),
			CreatedAt: formatTimestamp(r.CreatedAt),
			UpdatedAt: formatTimestamp(r.UpdatedAt),
		})
	}

	return ListEntriesResult{Entries: items}, nil
}

// BackfillEntryHosts fills in url_host for entries saved before HostFromURL
// understood URLs without a scheme (#2545). Entries that still have no host,
// such as ones with no URL at all, are left as they are. An entry that fails
// to decrypt is skipped rather than aborting the rest.
func BackfillEntryHosts(ctx context.Context, params BackfillEntryHostsParams) (BackfillEntryHostsResult, error) {
	rows, err := params.Queries.ListVaultEntriesWithoutHost(ctx)
	if err != nil {
		return BackfillEntryHostsResult{}, fmt.Errorf("list entries without host: %w", err)
	}

	updated := 0
	for _, row := range rows {
		plaintext, err := vaultcrypto.Decrypt(params.Key, row.Ciphertext, row.Nonce)
		if err != nil {
			continue
		}
		var payload EntryPayload
		if err := json.Unmarshal(plaintext, &payload); err != nil {
			continue
		}
		host := HostFromURL(payload.URL)
		if host == "" {
			continue
		}
		if err := params.Queries.UpdateVaultEntryHost(ctx, db.UpdateVaultEntryHostParams{UrlHost: host, ID: row.ID}); err != nil {
			return BackfillEntryHostsResult{Updated: updated}, fmt.Errorf("update entry host: %w", err)
		}
		updated++
	}
	return BackfillEntryHostsResult{Updated: updated}, nil
}

// GetEntry reads one entry and decrypts its payload. It returns
// [ErrEntryNotFound] when the id has no row.
func GetEntry(ctx context.Context, params GetEntryParams) (GetEntryResult, error) {
	entry, err := params.Queries.GetVaultEntry(ctx, params.ID)
	if errors.Is(err, sql.ErrNoRows) {
		return GetEntryResult{}, ErrEntryNotFound
	}
	if err != nil {
		return GetEntryResult{}, fmt.Errorf("get entry: %w", err)
	}

	plaintext, err := vaultcrypto.Decrypt(params.Key, entry.Ciphertext, entry.Nonce)
	if err != nil {
		return GetEntryResult{}, fmt.Errorf("decrypt entry: %w", err)
	}

	var payload EntryPayload
	if err := json.Unmarshal(plaintext, &payload); err != nil {
		return GetEntryResult{}, fmt.Errorf("unmarshal entry: %w", err)
	}

	return GetEntryResult{Entry: EntryDetail{
		ID:           entry.ID,
		Name:         entry.Name,
		URL:          payload.URL,
		URLHost:      entry.UrlHost,
		Username:     payload.Username,
		Password:     payload.Password,
		Notes:        payload.Notes,
		TOTPSecret:   payload.TOTPSecret,
		CustomFields: payload.CustomFields,
		FolderID:     fromNullInt64(entry.FolderID),
		CreatedAt:    formatTimestamp(entry.CreatedAt),
		UpdatedAt:    formatTimestamp(entry.UpdatedAt),
	}}, nil
}

// CreateEntry encrypts the supplied fields under the vault key and stores the
// resulting row.
func CreateEntry(ctx context.Context, params CreateEntryParams) (CreateEntryResult, error) {
	ciphertext, nonce, err := encryptFields(params.Key, params.Fields)
	if err != nil {
		return CreateEntryResult{}, err
	}

	entry, err := params.Queries.CreateVaultEntry(ctx, db.CreateVaultEntryParams{
		Name:       params.Fields.Name,
		UrlHost:    HostFromURL(params.Fields.URL),
		FolderID:   nullableInt64(params.Fields.FolderID),
		Ciphertext: ciphertext,
		Nonce:      nonce,
	})
	if err != nil {
		return CreateEntryResult{}, fmt.Errorf("create entry: %w", err)
	}

	return CreateEntryResult{Entry: EntryDetail{
		ID:           entry.ID,
		Name:         entry.Name,
		URL:          params.Fields.URL,
		URLHost:      entry.UrlHost,
		Username:     params.Fields.Username,
		Password:     params.Fields.Password,
		Notes:        params.Fields.Notes,
		TOTPSecret:   params.Fields.TOTPSecret,
		CustomFields: params.Fields.CustomFields,
		FolderID:     fromNullInt64(entry.FolderID),
		CreatedAt:    formatTimestamp(entry.CreatedAt),
		UpdatedAt:    formatTimestamp(entry.UpdatedAt),
	}}, nil
}

// UpdateEntry replaces an entry's stored fields. It returns
// [ErrEntryNotFound] when the id has no row.
func UpdateEntry(ctx context.Context, params UpdateEntryParams) (UpdateEntryResult, error) {
	if _, err := params.Queries.GetVaultEntry(ctx, params.ID); errors.Is(err, sql.ErrNoRows) {
		return UpdateEntryResult{}, ErrEntryNotFound
	} else if err != nil {
		return UpdateEntryResult{}, fmt.Errorf("get entry: %w", err)
	}

	ciphertext, nonce, err := encryptFields(params.Key, params.Fields)
	if err != nil {
		return UpdateEntryResult{}, err
	}

	if err := params.Queries.UpdateVaultEntry(ctx, db.UpdateVaultEntryParams{
		Name:       params.Fields.Name,
		UrlHost:    HostFromURL(params.Fields.URL),
		FolderID:   nullableInt64(params.Fields.FolderID),
		Ciphertext: ciphertext,
		Nonce:      nonce,
		ID:         params.ID,
	}); err != nil {
		return UpdateEntryResult{}, fmt.Errorf("update entry: %w", err)
	}

	return UpdateEntryResult{ID: params.ID}, nil
}

// DeleteEntry removes one entry.
func DeleteEntry(ctx context.Context, params DeleteEntryParams) (DeleteEntryResult, error) {
	if err := params.Queries.DeleteVaultEntry(ctx, params.ID); err != nil {
		return DeleteEntryResult{}, fmt.Errorf("delete entry: %w", err)
	}
	return DeleteEntryResult{Deleted: true}, nil
}

// encryptFields marshals the secret half of an entry and seals it under the
// vault key. Create and update share it because an update rewrites the whole
// payload rather than patching it.
func encryptFields(key []byte, fields EntryFields) (ciphertext, nonce []byte, err error) {
	payload := EntryPayload{
		URL:          fields.URL,
		Username:     fields.Username,
		Password:     fields.Password,
		Notes:        fields.Notes,
		TOTPSecret:   fields.TOTPSecret,
		CustomFields: fields.CustomFields,
	}

	plaintext, err := json.Marshal(payload)
	if err != nil {
		return nil, nil, fmt.Errorf("marshal entry: %w", err)
	}

	ciphertext, nonce, err = vaultcrypto.Encrypt(key, plaintext)
	if err != nil {
		return nil, nil, fmt.Errorf("encrypt entry: %w", err)
	}

	return ciphertext, nonce, nil
}
