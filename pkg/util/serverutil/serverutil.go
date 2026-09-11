// Package serverutil holds the HTTP building blocks the server layer is
// assembled from: the Response envelope handlers return, the Route/Router
// registration types that wire handlers onto gin, the HttpError type that lets
// a service function name its own status code, and the ports the server binds.
package serverutil

import (
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync/atomic"

	"github.com/gin-gonic/gin"
)

type ContentType string

const (
	ContentTypeHTML ContentType = "text/html"
	ContentTypeJSON ContentType = "application/json"
)

// HttpError is an error type that carries an HTTP status code.
// When returned from a service function and detected by WrapApiRoute,
// its StatusCode will be used instead of the default 500.
type HttpError struct {
	StatusCode int
	Message    string
}

func (e *HttpError) Error() string {
	return e.Message
}

// NewHttpError creates an HttpError with the given status code and message.
func NewHttpError(statusCode int, message string) *HttpError {
	return &HttpError{
		StatusCode: statusCode,
		Message:    message,
	}
}

// NewHttpErrorf creates an HttpError with the given status code and a formatted message.
func NewHttpErrorf(statusCode int, format string, args ...any) *HttpError {
	return &HttpError{
		StatusCode: statusCode,
		Message:    fmt.Sprintf(format, args...),
	}
}

type Response struct {
	StatusCode  int
	Data        any
	Error       error
	ContentType ContentType
}

func NewResponse() *Response {
	return (&Response{}).WithContentType(ContentTypeJSON).WithStatusCode(http.StatusOK).WithData(nil).WithError(nil)
}

func Accepted() *Response {
	return NewResponse().WithStatusCode(http.StatusAccepted)
}

func Ok() *Response {
	return NewResponse().WithStatusCode(http.StatusOK)
}

func BadRequest(err error) *Response {
	return NewResponse().WithStatusCode(http.StatusBadRequest).WithError(err)
}

func Unauthorized(err error) *Response {
	return NewResponse().WithStatusCode(http.StatusUnauthorized).WithError(err)
}

func InternalServerError(err error) *Response {
	return NewResponse().WithStatusCode(http.StatusInternalServerError).WithError(err)
}

// Conflict reports a request that cannot proceed against the current state —
// a chunk offered at the wrong offset of an upload session, for instance
// (#1629). Callers that want the client to resync set the headers carrying the
// true state before returning this.
func Conflict(err error) *Response {
	return NewResponse().WithStatusCode(http.StatusConflict).WithError(err)
}

func NotFound(err error) *Response {
	return NewResponse().WithStatusCode(http.StatusNotFound).WithError(err)
}

func ServiceUnavailable(err error) *Response {
	return NewResponse().WithStatusCode(http.StatusServiceUnavailable).WithError(err)
}

func (r *Response) WithContentType(contentType ContentType) *Response {
	r.ContentType = contentType
	return r
}

func (r *Response) WithStatusCode(statusCode int) *Response {
	r.StatusCode = statusCode
	return r
}

func (r *Response) WithData(data any) *Response {
	r.Data = data
	return r
}

func (r *Response) WithError(err error) *Response {
	r.Error = err
	return r
}

type Route struct {
	Path    string
	Method  string
	Handler gin.HandlerFunc
}

type Router interface {
	Routes() []*Route
}

func NewRoute(method, path string, handler gin.HandlerFunc) *Route {
	return &Route{
		Method:  method,
		Path:    path,
		Handler: handler,
	}
}

func ApiRoute(method, path string, handler func(c *gin.Context) *Response) *Route {
	return &Route{
		Method:  method,
		Path:    path,
		Handler: WrapApiRoute(handler),
	}
}

func RegisterRouterWithGroup(group *gin.RouterGroup, router Router) {
	for _, route := range router.Routes() {
		group.Handle(route.Method, route.Path, route.Handler)
	}
}

func RegisterRouter(engine *gin.Engine, router Router) {
	for _, route := range router.Routes() {
		engine.Handle(route.Method, route.Path, route.Handler)
	}
}

func WrapApiRoute(handler func(c *gin.Context) *Response) gin.HandlerFunc {
	return func(c *gin.Context) {
		resp := handler(c)
		// If handler wrote the response itself and returned nil, just return.
		if resp == nil {
			return
		}
		if resp.Data == nil && resp.Error == nil {
			c.Status(resp.StatusCode)
			return
		}
		// If the error wraps an HttpError, its status code takes precedence over
		// whatever status code the handler passed in. This means service functions
		// can signal HTTP semantics with fmt.Errorf("...: %w", httpErr) and the
		// HTTP layer will pick it up automatically.
		if resp.Error != nil {
			if httpErr, ok := errors.AsType[*HttpError](resp.Error); ok {
				resp.StatusCode = httpErr.StatusCode
			}
		}
		switch resp.ContentType {
		case ContentTypeHTML:
			if resp.Error != nil {
				c.String(resp.StatusCode, resp.Error.Error())
			} else {
				c.String(resp.StatusCode, "%v", resp.Data)
			}
		case ContentTypeJSON:
			if resp.Error != nil {
				c.JSON(resp.StatusCode, gin.H{"error": resp.Error.Error()})
			} else {
				c.JSON(resp.StatusCode, resp.Data)
			}
		default:
			c.String(http.StatusInternalServerError, "Unsupported content type")
		}
	}
}

// servingPort and servingTLS record the address the server actually bound, set
// once at startup by the server package. Callers that need to reach the server
// from inside the process (the tsnet remote-access proxy) must use these rather
// than guessing between ServerPort and ServerHttpsPort — guessing wrong means
// proxying plain HTTP at a TLS listener, or dialing a port nothing is on.
var (
	servingPort atomic.Int64
	servingTLS  atomic.Bool
)

// SetServingAddr records the port the server bound and whether it serves TLS.
func SetServingAddr(port int, tls bool) {
	servingPort.Store(int64(port))
	servingTLS.Store(tls)
}

// ServingPort returns the port the server actually bound. Falls back to the
// configured HTTPS/HTTP port when the server hasn't started yet.
func ServingPort() int {
	if p := servingPort.Load(); p != 0 {
		return int(p)
	}
	if servingTLS.Load() {
		return ServerHttpsPort()
	}
	return ServerPort()
}

// ServingTLS reports whether the server is serving HTTPS.
func ServingTLS() bool { return servingTLS.Load() }

// ServerPort returns the HTTP port the server listens on, read from the PORT
// environment variable. Defaults to 8080.
func ServerPort() int {
	p := os.Getenv("PORT")
	if p == "" {
		return 8080
	}
	n, err := strconv.Atoi(p)
	if err != nil {
		return 8080
	}
	return n
}

// ServerHttpsPort returns the HTTPS port the server listens on, read from the
// HTTPS_PORT environment variable. Defaults to 443.
//
// This is intentionally separate from ServerPort so that in-place binary
// upgrades on existing installations do not require a service-file edit: the
// old PORT=80 entry is left untouched and the new HTTPS_PORT=443 entry added
// only on fresh installs.
func ServerHttpsPort() int {
	p := os.Getenv("HTTPS_PORT")
	if p == "" {
		return 443
	}
	n, err := strconv.Atoi(p)
	if err != nil {
		return 443
	}
	return n
}

// TrustedProxies returns the peers whose X-Forwarded-For and X-Forwarded-Proto
// headers the server believes, read from the comma-separated IPs and CIDRs in
// QUARK_TRUSTED_PROXIES. Unset or blank, it is loopback only: the tsnet
// remote-access proxy is the one proxy a quark always has. Set, it replaces
// that default, so a deployment behind an ingress lists the ingress range.
// Any entry that is neither an IP nor a CIDR is an error naming it.
func TrustedProxies() ([]*net.IPNet, error) {
	value := os.Getenv("QUARK_TRUSTED_PROXIES")
	if strings.TrimSpace(value) == "" {
		value = "127.0.0.1,::1"
	}
	var nets []*net.IPNet
	for _, entry := range strings.Split(value, ",") {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		if _, n, err := net.ParseCIDR(entry); err == nil {
			nets = append(nets, n)
			continue
		}
		ip := net.ParseIP(entry)
		if ip == nil {
			return nil, fmt.Errorf("QUARK_TRUSTED_PROXIES: %q is neither an IP address nor a CIDR", entry)
		}
		if v4 := ip.To4(); v4 != nil {
			ip = v4
		}
		bits := len(ip) * 8
		nets = append(nets, &net.IPNet{IP: ip, Mask: net.CIDRMask(bits, bits)})
	}
	return nets, nil
}

// IsTrustedProxy reports whether ip is covered by TrustedProxies. An
// unparseable address, or an invalid QUARK_TRUSTED_PROXIES, is never trusted.
func IsTrustedProxy(ip string) bool {
	addr := net.ParseIP(ip)
	if addr == nil {
		return false
	}
	nets, err := TrustedProxies()
	if err != nil {
		return false
	}
	for _, n := range nets {
		if n.Contains(addr) {
			return true
		}
	}
	return false
}
