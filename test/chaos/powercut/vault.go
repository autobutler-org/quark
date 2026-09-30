package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/vaultcrypto"
	"github.com/autobutler-org/quark/pkg/util/vaultutil"
)

const (
	maxVaultEntries = 400
	vaultDeadline   = 30 * time.Second
	// rotateEvery is how many entries go in between master password changes,
	// each of which re-encrypts every entry in one transaction.
	rotateEvery = 10
)

// writeVault sets up a vault, then adds entries and rotates the master
// password between them until the mount dies under it or it runs out of work.
// A password change is written to the ledger as pending before it starts, so
// the check knows the vault may legitimately open with either password. The
// ledger names a master password by its generation, never by its text.
func writeVault(ctx context.Context, dir string, l *ledger) error {
	vault, err := db.ConnectToVaultDatabase(filepath.Join(dir, "vault.db"))
	if err != nil {
		return err
	}
	defer func() { _ = vault.Db.Close() }()
	session := vaultcrypto.NewVaultSession()

	generation := 0
	if err := l.ack("password-pending", strconv.Itoa(generation)); err != nil {
		return err
	}
	if _, err := vaultutil.Setup(ctx, vaultutil.SetupParams{
		Queries: vault.Queries, Session: session, MasterPassword: masterPassword(generation),
	}); err != nil {
		return fmt.Errorf("setup: %w", err)
	}
	if err := l.ack("password", strconv.Itoa(generation)); err != nil {
		return err
	}

	deadline := time.Now().Add(vaultDeadline)
	for i := 0; i < maxVaultEntries && time.Now().Before(deadline); i++ {
		key, ok := session.Key()
		if !ok {
			return errors.New("vault locked itself mid-run")
		}
		_, err := vaultutil.CreateEntry(ctx, vaultutil.CreateEntryParams{
			Queries: vault.Queries,
			Key:     key,
			Fields:  vaultutil.EntryFields{Name: entryName(i), Password: entrySecret(i)},
		})
		if err != nil {
			return fmt.Errorf("create %s: %w", entryName(i), err)
		}
		if err := l.ack("entry", entryName(i)); err != nil {
			return err
		}

		if i%rotateEvery != rotateEvery-1 {
			continue
		}
		next := generation + 1
		if err := l.ack("password-pending", strconv.Itoa(next)); err != nil {
			return err
		}
		if _, err := vaultutil.ChangePassword(ctx, vaultutil.ChangePasswordParams{
			VaultDB:         vault,
			Session:         session,
			OldKey:          key,
			CurrentPassword: masterPassword(generation),
			NewPassword:     masterPassword(next),
		}); err != nil {
			return fmt.Errorf("change password: %w", err)
		}
		if err := l.ack("password", strconv.Itoa(next)); err != nil {
			return err
		}
		generation = next
	}
	return nil
}

// checkVault holds what reached the disk to the bar: the database is
// consistent, it unlocks with the last master password that was acknowledged
// (or the one a change in flight was setting), every acknowledged entry is
// there with its secret, and every entry decrypts under that one key.
func checkVault(ctx context.Context, dir, ledgerPath string) error {
	lines, err := readLedger(ledgerPath)
	if err != nil {
		return err
	}
	// A generation of -1 means none was acknowledged, or none is pending.
	confirmed, pending := -1, -1
	var entries []string
	for _, fields := range lines {
		if len(fields) != 2 {
			return fmt.Errorf("malformed ledger line %q", fields)
		}
		switch fields[0] {
		case "password-pending", "password":
			n, err := strconv.Atoi(fields[1])
			if err != nil {
				return fmt.Errorf("malformed ledger line %q", fields)
			}
			if fields[0] == "password" {
				confirmed, pending = n, -1
			} else {
				pending = n
			}
		case "entry":
			entries = append(entries, fields[1])
		default:
			return fmt.Errorf("malformed ledger line %q", fields)
		}
	}

	path := filepath.Join(dir, "vault.db")
	if _, err := os.Stat(path); errors.Is(err, os.ErrNotExist) && confirmed < 0 {
		fmt.Println("vault: cut before the database was created")
		return nil
	}
	vault, err := db.ConnectToVaultDatabase(path)
	if err != nil {
		return fmt.Errorf("open: %w", err)
	}
	defer func() { _ = vault.Db.Close() }()

	var integrity string
	if err := vault.Db.QueryRow("PRAGMA integrity_check").Scan(&integrity); err != nil {
		return fmt.Errorf("integrity check: %w", err)
	}
	if integrity != "ok" {
		return fmt.Errorf("integrity check: %s", integrity)
	}

	if _, err := vault.Queries.GetVaultConfig(ctx); errors.Is(err, sql.ErrNoRows) {
		if confirmed >= 0 {
			return errors.New("vault reports uninitialized after its setup was acknowledged")
		}
		fmt.Println("vault: cut before setup committed")
		return nil
	} else if err != nil {
		return fmt.Errorf("read config: %w", err)
	}

	key, unlockedWith, err := unlockWithAny(ctx, vault, confirmed, pending)
	if err != nil {
		return err
	}
	defer vaultcrypto.ZeroKey(key)

	list, err := vaultutil.ListEntries(ctx, vaultutil.ListEntriesParams{Queries: vault.Queries})
	if err != nil {
		return fmt.Errorf("list entries: %w", err)
	}
	secrets := map[string]string{}
	var problems []error
	for _, item := range list.Entries {
		got, err := vaultutil.GetEntry(ctx, vaultutil.GetEntryParams{Queries: vault.Queries, Key: key, ID: item.ID})
		if err != nil {
			problems = append(problems, fmt.Errorf("entry %s does not decrypt under the vault key: %w", item.Name, err))
			continue
		}
		secrets[got.Entry.Name] = got.Entry.Password
	}
	for _, name := range entries {
		secret, ok := secrets[name]
		switch {
		case !ok:
			problems = append(problems, fmt.Errorf("acknowledged entry %s is missing", name))
		case secret != entrySecretFor(name):
			problems = append(problems, fmt.Errorf("acknowledged entry %s holds the wrong secret", name))
		}
	}

	fmt.Printf("vault: unlocked with master password #%d, %d acknowledged entries, %d stored, %d problems\n",
		unlockedWith, len(entries), len(list.Entries), len(problems))
	return errors.Join(problems...)
}

// unlockWithAny unlocks the vault with the confirmed master password or, when a
// change was in flight, the one it was setting, and returns the vault key and
// the generation that opened it.
func unlockWithAny(ctx context.Context, vault *db.DatabaseSqlc, generations ...int) ([]byte, int, error) {
	for _, generation := range generations {
		if generation < 0 {
			continue
		}
		session := vaultcrypto.NewVaultSession()
		_, err := vaultutil.Unlock(ctx, vaultutil.UnlockParams{
			Queries: vault.Queries, Session: session, MasterPassword: masterPassword(generation),
		})
		if errors.Is(err, vaultutil.ErrIncorrectMasterPassword) {
			continue
		}
		if err != nil {
			return nil, 0, fmt.Errorf("unlock: %w", err)
		}
		key, _ := session.Key()
		return key, generation, nil
	}
	return nil, 0, fmt.Errorf("vault unlocks with none of the acknowledged master password generations %v", generations)
}

// masterPassword is the master password of generation n.
func masterPassword(n int) string {
	return fmt.Sprintf("master-password-%03d", n)
}

func entryName(i int) string {
	return fmt.Sprintf("entry-%04d", i)
}

func entrySecret(i int) string {
	return fmt.Sprintf("secret-%04d", i)
}

func entrySecretFor(name string) string {
	var i int
	if _, err := fmt.Sscanf(name, "entry-%04d", &i); err != nil {
		return ""
	}
	return entrySecret(i)
}
