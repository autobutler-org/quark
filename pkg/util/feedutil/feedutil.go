// Package feedutil stores each account's feed subscriptions (#3714).
//
// A subscription belongs to one account and is not shared. Two accounts that
// follow the same feed each have their own row, so a later unread count has
// one owner. The feed URL can carry a private token, so it is a credential:
// every address is resolved and refused when it is private, loopback or
// link-local before anything is fetched, and no error or event repeats the
// URL. HTTP concerns stay with the caller, which maps the sentinel errors
// below onto status codes.
package feedutil

import (
	"context"
	"errors"
	"net"
	"time"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
)

// Bounds a subscription stays inside. A feed URL is short even with a token.
// A name or folder is a label, not a document.
const (
	maxURLLength   = 4096
	maxLabelLength = 200
	maxPageBytes   = 1 << 20
	maxRedirects   = 5
	maxCandidates  = 20
)

// Sentinel errors the caller maps onto a status code. Their text is written
// for a person to read, and none of it contains the address they sent.
var (
	// ErrInvalidURL reports an address that is not an http or https URL.
	ErrInvalidURL = errors.New("that address is not a valid http or https url")
	// ErrForbiddenAddress reports an address that resolves to a private,
	// loopback or link-local range, or that is not a public address at all.
	ErrForbiddenAddress = errors.New("that address is not allowed")
	// ErrUnresolved reports a hostname that did not resolve.
	ErrUnresolved = errors.New("that address could not be resolved")
	// ErrFetchFailed reports a page that could not be fetched. The address
	// itself was allowed.
	ErrFetchFailed = errors.New("could not fetch that page")
	// ErrNoFeed reports a page with no feed link.
	ErrNoFeed = errors.New("no feed was found on that page")
	// ErrSeveralFeeds reports a page that offers more than one feed. The
	// result's Candidates are the ones to subscribe to by URL.
	ErrSeveralFeeds = errors.New("that page offers several feeds")
	// ErrAlreadySubscribed reports a second subscription of the same feed
	// URL for one account.
	ErrAlreadySubscribed = errors.New("you already subscribe to that feed")
	// ErrNotFound reports a subscription id the account does not have,
	// another account's included.
	ErrNotFound = errors.New("feed not found")
	// ErrInvalidLabel reports a name or folder containing a control character.
	ErrInvalidLabel = errors.New("the name or folder is not valid")
	// ErrLabelTooLong reports a name or folder over the length limit.
	ErrLabelTooLong = errors.New("the name or folder is too long")
	// ErrNoChange reports an update that names neither a name nor a folder.
	ErrNoChange = errors.New("nothing to change")
	// ErrStoreFailed reports a failure while saving a subscription. It is
	// what a database error becomes when its text would repeat a feed URL.
	ErrStoreFailed = errors.New("could not save the feed")
)

// Feed is one account's subscription, as the API serves it to that account.
type Feed struct {
	ID                  int64      `json:"id"`
	URL                 string     `json:"url"`
	Title               string     `json:"title"`
	Name                string     `json:"name"`
	SiteLink            string     `json:"siteLink"`
	Icon                string     `json:"icon"`
	Folder              string     `json:"folder"`
	ETag                string     `json:"etag"`
	LastModified        string     `json:"lastModified"`
	LastFetchedAt       *time.Time `json:"lastFetchedAt"`
	LastError           string     `json:"lastError"`
	ConsecutiveFailures int64      `json:"consecutiveFailures"`
	CreatedAt           time.Time  `json:"createdAt"`
	UpdatedAt           time.Time  `json:"updatedAt"`
}

// Candidate is one feed a site page offered. URL is absolute.
type Candidate struct {
	URL   string `json:"url"`
	Title string `json:"title"`
	Type  string `json:"type"`
}

// IPLookup resolves a hostname to the addresses it publishes. A nil lookup
// uses the system resolver.
type IPLookup func(ctx context.Context, host string) ([]net.IP, error)

// AddParams subscribes the account to a feed.
type AddParams struct {
	Ctx      context.Context
	Queries  db.Querier
	UserID   int64
	URL      string
	Name     string
	Folder   string
	Discover bool
	// Lookup and Fetch are nil in production. Tests set them so a
	// subscription can be checked without the network.
	Lookup IPLookup
	Fetch  pageFetcher
}

// AddResult is the subscription, or the candidates when a site offers several
// and nothing was stored.
type AddResult struct {
	Feed       Feed
	Candidates []Candidate
}

// Add subscribes the account to a feed URL. When Discover is set, URL is a
// site page: it is fetched, and a single feed link is subscribed to. Several
// links return ErrSeveralFeeds and the candidates, and store nothing. No
// feed's entries are read.
func Add(params AddParams) (AddResult, error) {
	if params.UserID <= 0 {
		return AddResult{}, ErrNotFound
	}
	name, err := cleanLabel(params.Name)
	if err != nil {
		return AddResult{}, err
	}
	folder, err := cleanLabel(params.Folder)
	if err != nil {
		return AddResult{}, err
	}
	pageURL, err := checkAddress(params.Ctx, params.URL, params.Lookup)
	if err != nil {
		return AddResult{}, err
	}
	if !params.Discover {
		return insertFeed(params, pageURL.String(), "", "", "", name, folder)
	}

	fetcher := params.Fetch
	if fetcher == nil {
		fetcher = safeFetcher{lookup: params.Lookup}
	}
	page, err := fetcher.Fetch(params.Ctx, pageURL)
	if err != nil {
		return AddResult{}, scrubFetch(err)
	}
	found := candidatesFromPage(page)
	kept := keepPublic(params, found.candidates)
	switch len(kept) {
	case 0:
		return AddResult{}, ErrNoFeed
	case 1:
		return insertFeed(params, kept[0].URL, kept[0].Title, siteLink(params, page, found.feedDocument), checkedIcon(params, found.icon), name, folder)
	default:
		return AddResult{Candidates: kept}, ErrSeveralFeeds
	}
}

// ListParams names whose subscriptions to return.
type ListParams struct {
	Ctx     context.Context
	Queries db.Querier
	UserID  int64
}

// ListResult is an account's subscriptions, an empty slice when it has none.
type ListResult struct {
	Feeds []Feed
}

// List returns the account's subscriptions, folders first.
func List(params ListParams) (ListResult, error) {
	rows, err := params.Queries.ListFeeds(params.Ctx, params.UserID)
	if err != nil {
		return ListResult{}, scrubStore(err)
	}
	feeds := make([]Feed, 0, len(rows))
	for _, row := range rows {
		feeds = append(feeds, fromRow(row))
	}
	return ListResult{Feeds: feeds}, nil
}

// GetParams names one subscription of an account.
type GetParams struct {
	Ctx     context.Context
	Queries db.Querier
	UserID  int64
	ID      int64
}

// GetResult is that subscription.
type GetResult struct {
	Feed Feed
}

// Get returns one of the account's subscriptions, or ErrNotFound.
func Get(params GetParams) (GetResult, error) {
	row, err := params.Queries.GetFeed(params.Ctx, db.GetFeedParams{ID: params.ID, UserID: params.UserID})
	if err != nil {
		return GetResult{}, notFound(err)
	}
	return GetResult{Feed: fromRow(row)}, nil
}

// UpdateParams renames a subscription or moves it to a folder. A nil Name or
// Folder is left as it is. A pointer to an empty string clears it.
type UpdateParams struct {
	Ctx     context.Context
	Queries db.Querier
	UserID  int64
	ID      int64
	Name    *string
	Folder  *string
}

// UpdateResult is the subscription after the change.
type UpdateResult struct {
	Feed Feed
}

// Update renames one of the account's subscriptions or files it in a folder.
func Update(params UpdateParams) (UpdateResult, error) {
	if params.Name == nil && params.Folder == nil {
		return UpdateResult{}, ErrNoChange
	}
	row, err := params.Queries.GetFeed(params.Ctx, db.GetFeedParams{ID: params.ID, UserID: params.UserID})
	if err != nil {
		return UpdateResult{}, notFound(err)
	}
	name, folder := row.Name, row.Folder
	if params.Name != nil {
		name, err = cleanLabel(*params.Name)
		if err != nil {
			return UpdateResult{}, err
		}
	}
	if params.Folder != nil {
		folder, err = cleanLabel(*params.Folder)
		if err != nil {
			return UpdateResult{}, err
		}
	}
	updated, err := params.Queries.UpdateFeed(params.Ctx, db.UpdateFeedParams{
		Name: name, Folder: folder, ID: params.ID, UserID: params.UserID,
	})
	if err != nil {
		return UpdateResult{}, notFound(err)
	}
	return UpdateResult{Feed: fromRow(updated)}, nil
}

// DeleteParams names the subscription to remove.
type DeleteParams struct {
	Ctx     context.Context
	Queries db.Querier
	UserID  int64
	ID      int64
}

// DeleteResult is empty.
type DeleteResult struct{}

// Delete unsubscribes the account, or returns ErrNotFound.
func Delete(params DeleteParams) (DeleteResult, error) {
	n, err := params.Queries.DeleteFeed(params.Ctx, db.DeleteFeedParams{ID: params.ID, UserID: params.UserID})
	if err != nil {
		return DeleteResult{}, scrubStore(err)
	}
	if n == 0 {
		return DeleteResult{}, ErrNotFound
	}
	return DeleteResult{}, nil
}

// PublishChangedParams names whose subscription changed.
type PublishChangedParams struct {
	EventBus *eventbus.Bus
	UserID   int64
	FeedID   int64
}

// PublishChanged tells the account's other sessions that a subscription
// changed. The event names the row and the account, never the feed URL.
// Call it once the change has committed. A nil bus publishes nothing.
func PublishChanged(params PublishChangedParams) {
	if params.EventBus == nil || params.UserID == 0 {
		return
	}
	params.EventBus.Publish(eventbus.Event{
		Kind: eventbus.EventFeedChanged,
		Data: eventbus.FeedChanged{FeedID: params.FeedID, UserID: params.UserID},
	})
}
