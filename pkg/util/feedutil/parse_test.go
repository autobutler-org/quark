package feedutil

import (
	"net/url"
	"strings"
	"testing"
)

func TestCandidatesFromPage(t *testing.T) {
	base, err := url.Parse("https://user:site-secret@blog.example/posts/")
	if err != nil {
		t.Fatal(err)
	}
	body := `
		<!-- <link rel="alternate" type="application/rss+xml" href="http://127.0.0.1/comment"> -->
		<script>var s = '<link rel="alternate" type="application/rss+xml" href="http://127.0.0.1/script">';</script>
		<link rel="stylesheet" href="/style.css">
		<link type="application/rss+xml; charset=utf-8" href="/rss.xml" rel="alternate" title="Blog &amp; News">
		<link rel="alternate" type="application/atom+xml" title="Notes" href="https://other.example/atom.xml?token=feed-secret">
		<link REL=alternate TYPE=application/rss+xml HREF=also.xml>
		<link rel="icon" href="/favicon.ico">
		<link rel="alternate" type="text/html" href="/">
	`
	found := candidatesFromPage(pageBody{URL: base, ContentType: "text/html; charset=utf-8", Body: []byte(body)})
	if found.feedDocument {
		t.Fatal("parsed a site page as a feed document")
	}
	if len(found.candidates) != 3 {
		t.Fatalf("candidates = %+v", found.candidates)
	}
	if found.candidates[0].URL != "https://blog.example/rss.xml" || found.candidates[0].Title != "Blog & News" || found.candidates[0].Type != rssType {
		t.Fatalf("first = %+v", found.candidates[0])
	}
	if strings.Contains(found.candidates[0].URL, "site-secret") {
		t.Fatalf("relative link inherited the site token: %s", found.candidates[0].URL)
	}
	if found.candidates[1].URL != "https://other.example/atom.xml?token=feed-secret" || found.candidates[1].Type != atomType {
		t.Fatalf("second = %+v", found.candidates[1])
	}
	if found.candidates[2].URL != "https://blog.example/posts/also.xml" {
		t.Fatalf("unquoted = %+v", found.candidates[2])
	}
	if found.icon != "https://blog.example/favicon.ico" {
		t.Fatalf("icon = %s", found.icon)
	}
}

func TestCandidatesFromPageFeedDocument(t *testing.T) {
	base, err := url.Parse("https://blog.example/rss.xml?token=opaque")
	if err != nil {
		t.Fatal(err)
	}
	found := candidatesFromPage(pageBody{
		URL:         base,
		ContentType: "application/xml",
		Body:        []byte(`<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>`),
	})
	if !found.feedDocument || len(found.candidates) != 1 || found.candidates[0].Type != rssType {
		t.Fatalf("feed document = %+v", found)
	}
	if found.candidates[0].URL != base.String() {
		t.Fatalf("url = %s", found.candidates[0].URL)
	}
	htmlPage := candidatesFromPage(pageBody{
		URL:         base,
		ContentType: "application/octet-stream",
		Body:        []byte(`<!DOCTYPE html><html><link rel="alternate" type="application/atom+xml" href="/a"></html>`),
	})
	if htmlPage.feedDocument || len(htmlPage.candidates) != 1 {
		t.Fatalf("html sniff = %+v", htmlPage)
	}
}
