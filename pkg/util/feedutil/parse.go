package feedutil

import (
	"bytes"
	"html"
	"mime"
	"net/url"
	"strings"
)

const (
	rssType  = "application/rss+xml"
	atomType = "application/atom+xml"
)

// candidatesFromPage reads feed links out of a site page. A page that is
// itself a feed is one candidate, the page's own address, and no site link
// is taken from it. Link tags inside comments and script or style elements
// are ignored.
func candidatesFromPage(page pageBody) pageFeeds {
	if page.URL == nil {
		return pageFeeds{}
	}
	body := bytes.TrimPrefix(page.Body, []byte{0xEF, 0xBB, 0xBF})
	if ok, typ := sniffFeed(page.ContentType, body); ok {
		return pageFeeds{
			candidates:   []Candidate{{URL: page.URL.String(), Type: typ}},
			feedDocument: true,
		}
	}
	var found pageFeeds
	for _, attrs := range scanLinks(body) {
		href := resolveHref(page.URL, attrs["href"])
		if href == nil {
			continue
		}
		tokens := relTokens(attrs["rel"])
		if typ := feedMedia(attrs["type"]); typ != "" && tokens["alternate"] && len(found.candidates) < maxCandidates {
			found.candidates = append(found.candidates, Candidate{
				URL:   href.String(),
				Title: attrs["title"],
				Type:  typ,
			})
		}
		if found.icon == "" && (tokens["icon"] || tokens["apple-touch-icon"]) && !tokens["alternate"] {
			found.icon = href.String()
		}
	}
	return found
}

func sniffFeed(contentType string, body []byte) (bool, string) {
	switch mediaType(contentType) {
	case rssType:
		return true, rssType
	case atomType:
		return true, atomType
	case "text/html", "application/xhtml+xml":
		return false, ""
	}
	n := len(body)
	if n > 2048 {
		n = 2048
	}
	head := strings.ToLower(string(body[:n]))
	if strings.Contains(head, "<html") || strings.Contains(head, "<!doctype html") {
		return false, ""
	}
	if hasElement(head, "<rss") {
		return true, rssType
	}
	if hasElement(head, "<feed") {
		return true, atomType
	}
	return false, ""
}

func hasElement(head, tag string) bool {
	rest := head
	for {
		i := strings.Index(rest, tag)
		if i < 0 {
			return false
		}
		end := i + len(tag)
		if end >= len(rest) {
			return true
		}
		switch rest[end] {
		case '>', '/', ' ', '\n', '\r', '\t':
			return true
		}
		rest = rest[end:]
	}
}

func mediaType(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	mt, _, err := mime.ParseMediaType(raw)
	if err != nil {
		mt = strings.TrimSpace(strings.Split(raw, ";")[0])
	}
	return strings.ToLower(mt)
}

func feedMedia(raw string) string {
	switch mediaType(raw) {
	case rssType, atomType:
		return mediaType(raw)
	default:
		return ""
	}
}

func relTokens(rel string) map[string]bool {
	out := map[string]bool{}
	for _, token := range strings.Fields(strings.ToLower(rel)) {
		out[token] = true
	}
	return out
}

// resolveHref makes href absolute against base. A relative link does not
// inherit the base URL's userinfo, so a token on the site address is not
// copied onto the feed address.
func resolveHref(base *url.URL, href string) *url.URL {
	href = strings.TrimSpace(href)
	if href == "" || strings.HasPrefix(href, "#") || strings.ContainsAny(href, " \t\r\n\\") {
		return nil
	}
	ref, err := url.Parse(href)
	if err != nil {
		return nil
	}
	if ref.Scheme != "" && ref.Scheme != "http" && ref.Scheme != "https" {
		return nil
	}
	hadUser := ref.User != nil
	abs := base.ResolveReference(ref)
	if !hadUser {
		abs.User = nil
	}
	if (abs.Scheme != "http" && abs.Scheme != "https") || abs.Host == "" {
		return nil
	}
	return canonical(abs)
}

func scanLinks(body []byte) []map[string]string {
	lower := bytes.ToLower(body)
	var out []map[string]string
	for i := 0; i < len(body); {
		switch {
		case bytes.HasPrefix(lower[i:], []byte("<!--")):
			j := bytes.Index(lower[i+4:], []byte("-->"))
			if j < 0 {
				return out
			}
			i += 4 + j + 3
		case startsTag(lower, i, "script"):
			i = skipEnd(lower, i, "script")
		case startsTag(lower, i, "style"):
			i = skipEnd(lower, i, "style")
		case startsTag(lower, i, "link"):
			raw, next := readTag(body, i)
			if next <= i {
				i++
				continue
			}
			out = append(out, parseAttrs(raw))
			i = next
		default:
			i++
		}
	}
	return out
}

func startsTag(lower []byte, i int, name string) bool {
	if i >= len(lower) || lower[i] != '<' {
		return false
	}
	end := i + 1 + len(name)
	if end > len(lower) || string(lower[i+1:end]) != name {
		return false
	}
	if end == len(lower) {
		return true
	}
	switch lower[end] {
	case ' ', '\t', '\n', '\r', '/', '>':
		return true
	default:
		return false
	}
}

func skipEnd(lower []byte, i int, name string) int {
	j := bytes.Index(lower[i:], []byte("</"+name))
	if j < 0 {
		return len(lower)
	}
	k := i + j + 2 + len(name)
	for k < len(lower) && lower[k] != '>' {
		k++
	}
	if k < len(lower) {
		k++
	}
	return k
}

func readTag(body []byte, i int) (string, int) {
	var quote byte
	for j := i + 1; j < len(body); j++ {
		c := body[j]
		if quote != 0 {
			if c == quote {
				quote = 0
			}
			continue
		}
		if c == '"' || c == '\'' {
			quote = c
			continue
		}
		if c == '>' {
			return string(body[i : j+1]), j + 1
		}
	}
	return "", i
}

func parseAttrs(tag string) map[string]string {
	attrs := map[string]string{}
	i := 0
	if strings.HasPrefix(tag, "<") {
		i = 1
		for i < len(tag) && !isSpace(tag[i]) && tag[i] != '>' {
			i++
		}
	}
	for i < len(tag) {
		for i < len(tag) && isSpace(tag[i]) {
			i++
		}
		if i >= len(tag) || tag[i] == '/' || tag[i] == '>' {
			break
		}
		start := i
		for i < len(tag) && !isSpace(tag[i]) && tag[i] != '=' && tag[i] != '>' && tag[i] != '/' {
			i++
		}
		name := strings.ToLower(tag[start:i])
		for i < len(tag) && isSpace(tag[i]) {
			i++
		}
		val := ""
		if i < len(tag) && tag[i] == '=' {
			i++
			for i < len(tag) && isSpace(tag[i]) {
				i++
			}
			switch {
			case i < len(tag) && (tag[i] == '"' || tag[i] == '\''):
				q := tag[i]
				i++
				vstart := i
				for i < len(tag) && tag[i] != q {
					i++
				}
				val = tag[vstart:i]
				if i < len(tag) {
					i++
				}
			default:
				vstart := i
				for i < len(tag) && !isSpace(tag[i]) && tag[i] != '>' {
					i++
				}
				val = tag[vstart:i]
			}
		}
		if name != "" {
			attrs[name] = html.UnescapeString(strings.TrimSpace(val))
		}
	}
	return attrs
}

func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}
