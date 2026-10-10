package vfs

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/autobutler-org/quark/internal/db"
)

// Get returns all metadata for (namespace, path) as a map of key → JSON value.
// Returns an empty map (not an error) if no metadata is set.
func (s *SQLiteMetadataStore) Get(ctx context.Context, namespace, path string) (map[string]json.RawMessage, error) {
	rows, err := s.queries.ListVFSMetadata(ctx, db.ListVFSMetadataParams{Namespace: namespace, Path: path})
	if err != nil {
		return nil, fmt.Errorf("vfs metadata get: %w", err)
	}

	result := make(map[string]json.RawMessage, len(rows))
	for _, row := range rows {
		result[row.Key] = json.RawMessage(row.Value)
	}
	return result, nil
}

// Set merges kv into existing metadata for (namespace, path).
// Keys in kv overwrite existing values; absent keys are unchanged.
func (s *SQLiteMetadataStore) Set(ctx context.Context, namespace, path string, kv map[string]json.RawMessage) error {
	if len(kv) == 0 {
		return nil
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("vfs metadata set begin tx: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	qtx := s.queries.WithTx(tx)
	for key, value := range kv {
		err := qtx.UpsertVFSMetadata(ctx, db.UpsertVFSMetadataParams{
			Namespace: namespace,
			Path:      path,
			Key:       key,
			Value:     string(value),
		})
		if err != nil {
			return fmt.Errorf("vfs metadata set exec key %q: %w", key, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("vfs metadata set commit: %w", err)
	}
	return nil
}

// DeleteKeys removes specific keys from metadata for (namespace, path).
// Deleting a non-existent key is a no-op.
func (s *SQLiteMetadataStore) DeleteKeys(ctx context.Context, namespace, path string, keys []string) error {
	if len(keys) == 0 {
		return nil
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("vfs metadata delete keys begin tx: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck

	qtx := s.queries.WithTx(tx)
	for _, key := range keys {
		err := qtx.DeleteVFSMetadataKey(ctx, db.DeleteVFSMetadataKeyParams{Namespace: namespace, Path: path, Key: key})
		if err != nil {
			return fmt.Errorf("vfs metadata delete key %q: %w", key, err)
		}
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("vfs metadata delete keys commit: %w", err)
	}
	return nil
}

// Query returns all (namespace, path) entries where the given key equals value.
// Pass value=nil to match any entry that has the key set (existence check).
func (s *SQLiteMetadataStore) Query(ctx context.Context, namespace, key string, value json.RawMessage) ([]MetaEntry, error) {
	var paths []string
	var err error
	if value == nil {
		paths, err = s.queries.ListVFSMetadataPathsByKey(ctx, db.ListVFSMetadataPathsByKeyParams{Namespace: namespace, Key: key})
	} else {
		paths, err = s.queries.ListVFSMetadataPathsByKeyValue(ctx, db.ListVFSMetadataPathsByKeyValueParams{
			Namespace: namespace,
			Key:       key,
			Value:     string(value),
		})
	}
	if err != nil {
		return nil, fmt.Errorf("vfs metadata query: %w", err)
	}

	// For each matched path, fetch all metadata to populate MetaEntry.Meta.
	entries := make([]MetaEntry, 0, len(paths))
	for _, p := range paths {
		meta, err := s.Get(ctx, namespace, p)
		if err != nil {
			return nil, err
		}
		entries = append(entries, MetaEntry{
			Namespace: namespace,
			Path:      p,
			Meta:      meta,
		})
	}
	return entries, nil
}
