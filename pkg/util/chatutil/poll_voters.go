package chatutil

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
	"github.com/autobutler-org/quark/pkg/util/storageutil"
)

// voterKeyBytes is the size of the poll voter key.
const voterKeyBytes = 32

// VoterKeyPath is where the poll voter key lives in dataDir (#3942): beside
// the database, never in it, and outside the files directory every snapshot
// copies and the bundle carries.
func VoterKeyPath(dataDir string) string {
	return filepath.Join(dataDir, "secrets", "chat-poll-voter.key")
}

// TagAnonymousPollAnswersParams converts the anonymous answers stored before
// voter tags.
type TagAnonymousPollAnswersParams struct {
	Ctx     context.Context
	Queries db.Querier
	DataDir string
}

// TagAnonymousPollAnswersResult counts what the pass changed.
type TagAnonymousPollAnswersResult struct {
	// Tagged answers now hold a voter tag and no account.
	Tagged int
	// Dropped answers were superseded by a newer tagged answer from the same
	// account, so they were deleted rather than tagged.
	Dropped int
}

// TagAnonymousPollAnswers swaps the account id of every anonymous poll's
// answer still holding one for its voter tag (#3942). Migration 052 cannot,
// because the key is not in the database. The server runs it at every start;
// once every row is converted it finds nothing to do.
func TagAnonymousPollAnswers(params TagAnonymousPollAnswersParams) (TagAnonymousPollAnswersResult, error) {
	var result TagAnonymousPollAnswersResult
	rows, err := params.Queries.ListUntaggedAnonymousChatPollAnswers(params.Ctx)
	if err != nil || len(rows) == 0 {
		return result, err
	}
	key, err := voterKey(params.DataDir)
	if err != nil {
		return result, err
	}
	for _, row := range rows {
		err := params.Queries.TagChatPollAnswer(params.Ctx, db.TagChatPollAnswerParams{
			ID: row.ID, VoterTag: voterTag(key, row.MessageID, row.UserID.Int64),
		})
		if sqlutil.IsUniqueConstraintErr(err) {
			// The account answered again after the poll gained tags; that
			// answer is the newer one.
			err = params.Queries.DeleteChatPollAnswer(params.Ctx, row.ID)
			result.Dropped++
		} else if err == nil {
			result.Tagged++
		}
		if err != nil {
			return result, fmt.Errorf("tag anonymous poll answer %d: %w", row.ID, err)
		}
	}
	return result, nil
}

// DeleteAnonymousPollAnswersParams removes a deleted account's anonymous
// answers.
type DeleteAnonymousPollAnswersParams struct {
	Ctx     context.Context
	Queries db.Querier
	DataDir string
	UserID  int64
}

// DeleteAnonymousPollAnswers removes the account's answer from every
// anonymous poll, found by its voter tag. A named answer goes with the account
// by ON DELETE CASCADE; an anonymous one names no account, so whoever deletes
// the account calls this after (#3942).
func DeleteAnonymousPollAnswers(params DeleteAnonymousPollAnswersParams) error {
	// ponytail: one DELETE per anonymous poll, fine at household scale.
	polls, err := params.Queries.ListAnonymousChatPollIDs(params.Ctx)
	if err != nil || len(polls) == 0 {
		return err
	}
	key, err := voterKey(params.DataDir)
	if err != nil {
		return err
	}
	for _, messageID := range polls {
		if err := params.Queries.DeleteChatPollAnswerByVoterTag(params.Ctx, db.DeleteChatPollAnswerByVoterTagParams{
			MessageID: messageID, VoterTag: voterTag(key, messageID, params.UserID),
		}); err != nil {
			return fmt.Errorf("delete anonymous answer to poll %d: %w", messageID, err)
		}
	}
	return nil
}

// voterKey reads the poll voter key from dataDir, making it the first time.
// A key of the wrong size is an error rather than replaced: a new key would
// orphan every voter tag already stored.
func voterKey(dataDir string) ([]byte, error) {
	if dataDir == "" {
		return nil, errors.New("chat: no data directory to keep the poll voter key in")
	}
	path := VoterKeyPath(dataDir)
	key, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		key = make([]byte, voterKeyBytes)
		_, _ = rand.Read(key)
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			return nil, fmt.Errorf("make the poll voter key's directory: %w", err)
		}
		err = storageutil.WriteFileAtomicExclusivePerm(path, bytes.NewReader(key), 0o600)
		if errors.Is(err, fs.ErrExist) {
			// Another request made it first; theirs is the key.
			key, err = os.ReadFile(path)
		} else if err == nil {
			log.Printf("chat: made the poll voter key at %s", path)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("read the poll voter key at %s: %w", path, err)
	}
	if len(key) != voterKeyBytes {
		return nil, fmt.Errorf("the poll voter key at %s is %d bytes, want %d: put back the original, "+
			"or remove it to start a new one, which forgets who answered each anonymous poll", path, len(key), voterKeyBytes)
	}
	return key, nil
}

// voterTag is the account's tag on one anonymous poll: HMAC-SHA256 under the
// voter key over the poll's message id and the account id. Without the key,
// the database and its backups cannot tie a tag to an account.
func voterTag(key []byte, messageID, userID int64) []byte {
	mac := hmac.New(sha256.New, key)
	var buf [16]byte
	binary.BigEndian.PutUint64(buf[:8], uint64(messageID))
	binary.BigEndian.PutUint64(buf[8:], uint64(userID))
	mac.Write([]byte("quark-chat-poll-voter-v1"))
	mac.Write(buf[:])
	return mac.Sum(nil)
}
