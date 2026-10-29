package feedutil

import (
	"context"
	"net/url"
)

// pageBody is one fetched page. URL is the final address after redirects.
type pageBody struct {
	URL         *url.URL
	ContentType string
	Body        []byte
}

// pageFetcher fetches one page. The production fetcher refuses a private,
// loopback or link-local address. Tests pass a fake.
type pageFetcher interface {
	Fetch(ctx context.Context, page *url.URL) (pageBody, error)
}

// pageFeeds is what a fetched page offered.
type pageFeeds struct {
	candidates   []Candidate
	icon         string
	feedDocument bool
}
