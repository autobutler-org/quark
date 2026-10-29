package feedutil

import (
	"database/sql"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/sqlutil"
)

func fromRow(row db.Feed) Feed {
	var fetched *time.Time
	if row.LastFetchedAt.Valid {
		t := row.LastFetchedAt.Time.UTC()
		fetched = &t
	}
	return Feed{
		ID:                  row.ID,
		URL:                 row.Url,
		Title:               row.Title,
		Name:                row.Name,
		SiteLink:            row.SiteLink,
		Icon:                row.Icon,
		Folder:              row.Folder,
		ETag:                row.Etag,
		LastModified:        row.LastModified,
		LastFetchedAt:       fetched,
		LastError:           row.LastError,
		ConsecutiveFailures: row.ConsecutiveFailures,
		CreatedAt:           row.CreatedAt.UTC(),
		UpdatedAt:           row.UpdatedAt.UTC(),
	}
}

func insertFeed(params AddParams, feedURL, title, site, icon, name, folder string) (AddResult, error) {
	if params.Queries == nil {
		return AddResult{}, ErrStoreFailed
	}
	row, err := params.Queries.CreateFeed(params.Ctx, db.CreateFeedParams{
		UserID:   params.UserID,
		Url:      feedURL,
		Title:    title,
		Name:     name,
		SiteLink: site,
		Icon:     icon,
		Folder:   folder,
	})
	if err != nil {
		return AddResult{}, scrubStore(err, feedURL, params.URL)
	}
	return AddResult{Feed: fromRow(row)}, nil
}

// keepPublic drops candidates whose address is not allowed and repeats.
func keepPublic(params AddParams, in []Candidate) []Candidate {
	kept := make([]Candidate, 0, len(in))
	seen := map[string]bool{}
	for _, c := range in {
		checked, err := checkAddress(params.Ctx, c.URL, params.Lookup)
		if err != nil {
			continue
		}
		c.URL = checked.String()
		if seen[c.URL] {
			continue
		}
		seen[c.URL] = true
		c.Title = cleanTitle(c.Title)
		kept = append(kept, c)
		if len(kept) == maxCandidates {
			break
		}
	}
	return kept
}

func siteLink(params AddParams, page pageBody, feedDocument bool) string {
	if feedDocument || page.URL == nil {
		return ""
	}
	checked, err := checkAddress(params.Ctx, page.URL.String(), params.Lookup)
	if err != nil {
		return ""
	}
	return checked.String()
}

func checkedIcon(params AddParams, icon string) string {
	if icon == "" {
		return ""
	}
	checked, err := checkAddress(params.Ctx, icon, params.Lookup)
	if err != nil {
		return ""
	}
	return checked.String()
}

func cleanLabel(s string) (string, error) {
	s = strings.TrimSpace(s)
	if utf8.RuneCountInString(s) > maxLabelLength {
		return "", ErrLabelTooLong
	}
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return "", ErrInvalidLabel
		}
	}
	return s, nil
}

func cleanTitle(s string) string {
	s = strings.TrimSpace(s)
	s = strings.Map(func(r rune) rune {
		if r < 0x20 || r == 0x7f {
			return -1
		}
		return r
	}, s)
	if utf8.RuneCountInString(s) <= maxLabelLength {
		return s
	}
	return string([]rune(s)[:maxLabelLength])
}

func notFound(err error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return ErrNotFound
	}
	return scrubStore(err)
}

// scrubStore hides a database error whose text repeats a feed URL. A unique
// violation becomes ErrAlreadySubscribed before that text is read, which is
// what keeps a PostgreSQL detail line from leaving the process.
func scrubStore(err error, secrets ...string) error {
	if err == nil {
		return nil
	}
	if sqlutil.IsUniqueConstraintErr(err) {
		return ErrAlreadySubscribed
	}
	msg := err.Error()
	for _, secret := range secrets {
		if secret != "" && strings.Contains(msg, secret) {
			return ErrStoreFailed
		}
	}
	if strings.Contains(msg, "://") {
		return ErrStoreFailed
	}
	return err
}

// scrubFetch returns a sentinel. A transport error wraps the address it
// tried, and that wrapper must not be what a caller turns into a response.
func scrubFetch(err error) error {
	switch {
	case errors.Is(err, ErrForbiddenAddress):
		return ErrForbiddenAddress
	case errors.Is(err, ErrUnresolved):
		return ErrUnresolved
	case errors.Is(err, ErrInvalidURL):
		return ErrInvalidURL
	default:
		return ErrFetchFailed
	}
}
