package serverutil

import (
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// credentialQueryParams are the query parameters that carry a credential:
// the session token the media, download and event-stream routes accept in
// the URL (#1332), because a <video> tag or an EventSource cannot send a
// header.
var credentialQueryParams = map[string]bool{"token": true}

// redactedValue replaces a credential in a logged URL.
const redactedValue = "REDACTED"

// redactQuery returns path with the value of every credential query
// parameter replaced by [redactedValue]. Everything else — the other
// parameters, their order and their encoding — is left as the client sent it,
// so the log line still says what was asked for.
func redactQuery(path string) string {
	base, raw, ok := strings.Cut(path, "?")
	if !ok {
		return path
	}
	parts := strings.Split(raw, "&")
	for i, part := range parts {
		key, _, _ := strings.Cut(part, "=")
		// A key that does not unescape cannot be one the server reads either,
		// but compare the raw key too so an odd encoding is not an escape.
		name, err := url.QueryUnescape(key)
		if err != nil {
			name = key
		}
		if credentialQueryParams[name] {
			parts[i] = key + "=" + redactedValue
		}
	}
	return base + "?" + strings.Join(parts, "&")
}

// redactedLogFormatter is gin's default access-log line, with credentials
// taken out of the path first.
func redactedLogFormatter(param gin.LogFormatterParams) string {
	param.Path = redactQuery(param.Path)
	return defaultLogFormat(param)
}

// defaultLogFormat reproduces gin's own default formatter, which gin does not
// export, so the access log reads the same as it did under gin.Default.
func defaultLogFormat(param gin.LogFormatterParams) string {
	var statusColor, methodColor, resetColor, latencyColor string
	if param.IsOutputColor() {
		statusColor = param.StatusCodeColor()
		methodColor = param.MethodColor()
		resetColor = param.ResetColor()
		latencyColor = param.LatencyColor()
	}

	switch {
	case param.Latency > time.Minute:
		param.Latency = param.Latency.Truncate(time.Second * 10)
	case param.Latency > time.Second:
		param.Latency = param.Latency.Truncate(time.Millisecond * 10)
	case param.Latency > time.Millisecond:
		param.Latency = param.Latency.Truncate(time.Microsecond * 10)
	}

	return fmt.Sprintf("[GIN] %v |%s %3d %s|%s %8v %s| %15s |%s %-7s %s %#v\n%s",
		param.TimeStamp.Format("2006/01/02 - 15:04:05"),
		statusColor, param.StatusCode, resetColor,
		latencyColor, param.Latency, resetColor,
		param.ClientIP,
		methodColor, param.Method, resetColor,
		param.Path,
		param.ErrorMessage,
	)
}
