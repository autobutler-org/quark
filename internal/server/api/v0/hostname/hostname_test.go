package v0_hostname_test

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"testing"

	v0_hostname "github.com/autobutler-org/quark/internal/server/api/v0/hostname"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/eventbus"
	"github.com/autobutler-org/quark/pkg/util/hostnameutil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"

	"github.com/gin-gonic/gin"
)

type hostnameHarness struct {
	engine *gin.Engine
	// calls records every command the handlers ran, stdin included.
	calls  *[][]string
	events <-chan eventbus.Event
}

// newHostnameHarness mounts the routes over a fake host called quark, which
// Avahi advertises as advertised.
func newHostnameHarness(t *testing.T, reason hostnameutil.Reason, advertised string) hostnameHarness {
	t.Helper()
	calls := &[][]string{}
	// The fake keeps the name the helper was given, as the real host does.
	hostname := "quark"
	system := hostnameutil.System{
		Unavailable: func() hostnameutil.Reason { return reason },
		Hostname:    func() (string, error) { return hostname, nil },
		Run: func(_ context.Context, stdin io.Reader, name string, args ...string) ([]byte, error) {
			in := ""
			if stdin != nil {
				b, err := io.ReadAll(stdin)
				if err != nil {
					t.Fatal(err)
				}
				in = string(b)
			}
			*calls = append(*calls, append(append([]string{name}, args...), "stdin="+in))
			switch name {
			case "sudo":
				hostname = strings.TrimSuffix(in, "\n")
				return nil, nil
			case "busctl":
				return []byte(`{"type":"s","data":["` + advertised + `"]}`), nil
			}
			return nil, errors.New("unexpected command " + name)
		},
		RefreshCertificate: func() error { return nil },
	}
	bus := eventbus.New()
	events, unsubscribe := bus.Subscribe("test")
	t.Cleanup(unsubscribe)
	deps := deputil.NewDependencies().WithHostnameSystem(system).WithEventBus(bus)
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	serverutil.RegisterRouterWithGroup(engine.Group("/api/v0"), v0_hostname.NewRouter())
	return hostnameHarness{engine: engine, calls: calls, events: events}
}

func (h hostnameHarness) do(method, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, "/api/v0/hostname", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	h.engine.ServeHTTP(w, req)
	return w
}

// published drains the hostname_changed events so far.
func (h hostnameHarness) published() []eventbus.HostnameChanged {
	var got []eventbus.HostnameChanged
	for {
		select {
		case evt := <-h.events:
			if changed, ok := evt.Data.(eventbus.HostnameChanged); ok && evt.Kind == eventbus.EventHostnameChanged {
				got = append(got, changed)
			}
		default:
			return got
		}
	}
}

// decode reads a response into exactly the keys the app's model will read.
func decode(t *testing.T, w *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var got map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &got); err != nil {
		t.Fatalf("body %q: %v", w.Body.String(), err)
	}
	return got
}

func TestGetHostname(t *testing.T) {
	h := newHostnameHarness(t, hostnameutil.ReasonNone, "quark-2")
	w := h.do(http.MethodGet, "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET = %d: %s", w.Code, w.Body.String())
	}
	got := decode(t, w)
	want := map[string]any{"available": true, "hostname": "quark", "advertisedHostname": "quark-2"}
	if len(got) != len(want) {
		t.Errorf("GET = %v, want %v", got, want)
	}
	for k, v := range want {
		if got[k] != v {
			t.Errorf("GET %s = %v, want %v", k, got[k], v)
		}
	}
}

// A Mac, or a Quark run by hand, still says what it is called, and gives the
// reason the app hides the rename field for.
func TestGetHostname_Unavailable(t *testing.T) {
	h := newHostnameHarness(t, hostnameutil.ReasonUnsupportedOS, "quark")
	w := h.do(http.MethodGet, "")
	if w.Code != http.StatusOK {
		t.Fatalf("GET = %d: %s", w.Code, w.Body.String())
	}
	got := decode(t, w)
	if got["available"] != false || got["reason"] != "unsupported_os" || got["hostname"] != "quark" {
		t.Errorf("GET = %v, want unavailable for unsupported_os and still named quark", got)
	}
	if _, ok := got["advertisedHostname"]; ok || len(*h.calls) != 0 {
		t.Errorf("GET = %v after running %v, want no advertised name and no commands", got, *h.calls)
	}

	w = h.do(http.MethodPut, `{"hostname":"kitchen"}`)
	if w.Code != http.StatusConflict {
		t.Errorf("PUT on a Quark that can't be renamed = %d, want 409: %s", w.Code, w.Body.String())
	}
	if len(*h.calls) != 0 || len(h.published()) != 0 {
		t.Errorf("a refused rename ran %v and published events", *h.calls)
	}
}

// A rename hands the name to the root helper on stdin, answers with the name
// the device ends up advertising, tells every open app, and shows on the next
// read.
func TestSetHostname(t *testing.T) {
	h := newHostnameHarness(t, hostnameutil.ReasonNone, "kitchen-2")
	w := h.do(http.MethodPut, `{"hostname":"kitchen"}`)
	if w.Code != http.StatusOK {
		t.Fatalf("PUT = %d: %s", w.Code, w.Body.String())
	}
	got := decode(t, w)
	if got["available"] != true || got["hostname"] != "kitchen" || got["advertisedHostname"] != "kitchen-2" {
		t.Errorf("PUT = %v, want kitchen advertised as kitchen-2", got)
	}
	if want := []string{"sudo", "-n", hostnameutil.HelperPath, "stdin=kitchen\n"}; len(*h.calls) == 0 || !slices.Equal((*h.calls)[0], want) {
		t.Errorf("PUT ran %v, want %v first", *h.calls, want)
	}
	want := []eventbus.HostnameChanged{{Hostname: "kitchen", AdvertisedHostname: "kitchen-2"}}
	if events := h.published(); !slices.Equal(events, want) {
		t.Errorf("published %+v, want %+v", events, want)
	}
	if got := decode(t, h.do(http.MethodGet, "")); got["hostname"] != "kitchen" {
		t.Errorf("GET after the rename = %v, want kitchen", got)
	}
}

func TestSetHostname_RejectsInvalidNames(t *testing.T) {
	h := newHostnameHarness(t, hostnameutil.ReasonNone, "quark")
	for _, body := range []string{
		``,
		`{}`,
		`{"hostname":""}`,
		`{"hostname":42}`,
		`{"hostname":"Kitchen"}`,
		`{"hostname":"-kitchen"}`,
		`{"hostname":"kitchen.local"}`,
		`{"hostname":"kitchen; reboot"}`,
		`{"hostname":"$(reboot)"}`,
		`{"hostname":"kitchen\nreboot"}`,
		`{"hostname":"` + strings.Repeat("a", 64) + `"}`,
		`{"hostname":"` + strings.Repeat("a", 4096) + `"}`,
	} {
		w := h.do(http.MethodPut, body)
		if w.Code != http.StatusBadRequest {
			t.Errorf("PUT %.60s = %d, want 400", body, w.Code)
		}
		if errText, _ := decode(t, w)["error"].(string); errText == "" {
			t.Errorf("PUT %.60s = %s, want a message saying why", body, w.Body.String())
		}
	}
	if len(*h.calls) != 0 || len(h.published()) != 0 {
		t.Errorf("rejected names ran %v and published events", *h.calls)
	}
}
