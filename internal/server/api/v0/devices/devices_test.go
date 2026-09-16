package v0_devices_test

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/autobutler-org/quark/internal/db"
	"github.com/autobutler-org/quark/internal/db/dbtest"
	v0_devices "github.com/autobutler-org/quark/internal/server/api/v0/devices"
	"github.com/autobutler-org/quark/pkg/util/ctxutil"
	"github.com/autobutler-org/quark/pkg/util/deputil"
	"github.com/autobutler-org/quark/pkg/util/serverutil"
	"github.com/gin-gonic/gin"
	_ "modernc.org/sqlite"
)

func newDevicesTestDB(t *testing.T) (*sql.DB, *db.Queries) {
	t.Helper()
	database := dbtest.NewDB(t)
	return database.Db, database.Queries
}

func newDevicesEngine(t *testing.T, sqlDB *sql.DB, queries *db.Queries) *gin.Engine {
	t.Helper()
	deps := deputil.NewDependencies().WithDatabase(&db.DatabaseSqlc{Db: sqlDB, Queries: queries})
	gin.SetMode(gin.TestMode)
	engine := gin.New()
	engine.Use(func(c *gin.Context) {
		c = ctxutil.With(c, "deps", deps)
		c.Next()
	})
	group := engine.Group("/api/v0")
	serverutil.RegisterRouterWithGroup(group, v0_devices.NewRouter())
	// routes.go mounts this one behind RequireAdmin.
	serverutil.RegisterRouterWithGroup(group, v0_devices.NewAdminRouter())
	return engine
}

func doDeviceReq(engine *gin.Engine, method, path string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, nil)
	w := httptest.NewRecorder()
	engine.ServeHTTP(w, req)
	return w
}

// TestListDevices_Empty verifies GET /devices returns an empty array when no
// devices have been recorded.
func TestListDevices_Empty(t *testing.T) {
	sqlDB, queries := newDevicesTestDB(t)
	engine := newDevicesEngine(t, sqlDB, queries)

	w := doDeviceReq(engine, http.MethodGet, "/api/v0/devices")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /devices returned %d: %s", w.Code, w.Body.String())
	}
	var devices []v0_devices.ConnectedDeviceJSON
	json.Unmarshal(w.Body.Bytes(), &devices)
	if devices == nil {
		t.Error("expected empty slice, not null")
	}
	if len(devices) != 0 {
		t.Errorf("expected 0 devices, got %d", len(devices))
	}
}

// TestListDevices_ReturnsUpsertedDevices verifies that devices upserted into
// the DB appear in GET /devices.
func TestListDevices_ReturnsUpsertedDevices(t *testing.T) {
	sqlDB, queries := newDevicesTestDB(t)
	engine := newDevicesEngine(t, sqlDB, queries)
	ctx := context.Background()

	_, err := queries.UpsertConnectedDevice(ctx, db.UpsertConnectedDeviceParams{
		IpAddress: "192.168.1.10",
		UserAgent: "Quark-Flutter/1.0",
	})
	if err != nil {
		t.Fatalf("UpsertConnectedDevice: %v", err)
	}

	w := doDeviceReq(engine, http.MethodGet, "/api/v0/devices")
	if w.Code != http.StatusOK {
		t.Fatalf("GET /devices returned %d: %s", w.Code, w.Body.String())
	}
	var devices []v0_devices.ConnectedDeviceJSON
	json.Unmarshal(w.Body.Bytes(), &devices)
	if len(devices) != 1 {
		t.Fatalf("expected 1 device, got %d; body: %s", len(devices), w.Body.String())
	}
	if devices[0].IPAddress != "192.168.1.10" {
		t.Errorf("IPAddress = %q; want '192.168.1.10'", devices[0].IPAddress)
	}
	if devices[0].UserAgent != "Quark-Flutter/1.0" {
		t.Errorf("UserAgent = %q; want 'Quark-Flutter/1.0'", devices[0].UserAgent)
	}
}

// TestDeleteDevice_RemovesEntry verifies DELETE /devices/:id removes the
// device so it no longer appears in the listing.
func TestDeleteDevice_RemovesEntry(t *testing.T) {
	sqlDB, queries := newDevicesTestDB(t)
	engine := newDevicesEngine(t, sqlDB, queries)
	ctx := context.Background()

	device, err := queries.UpsertConnectedDevice(ctx, db.UpsertConnectedDeviceParams{
		IpAddress: "10.0.0.5",
		UserAgent: "test-agent",
	})
	if err != nil {
		t.Fatalf("UpsertConnectedDevice: %v", err)
	}

	w := doDeviceReq(engine, http.MethodDelete,
		fmt.Sprintf("/api/v0/devices/%d", device.ID))
	if w.Code != http.StatusOK {
		t.Fatalf("DELETE returned %d: %s", w.Code, w.Body.String())
	}

	// Verify gone from listing.
	w2 := doDeviceReq(engine, http.MethodGet, "/api/v0/devices")
	var devices []v0_devices.ConnectedDeviceJSON
	json.Unmarshal(w2.Body.Bytes(), &devices)
	if len(devices) != 0 {
		t.Errorf("expected 0 devices after delete, got %d", len(devices))
	}
}

// TestDeleteDevice_InvalidID verifies DELETE /devices/:id returns 400 for a
// non-integer ID.
func TestDeleteDevice_InvalidID(t *testing.T) {
	sqlDB, queries := newDevicesTestDB(t)
	engine := newDevicesEngine(t, sqlDB, queries)

	w := doDeviceReq(engine, http.MethodDelete, "/api/v0/devices/not-a-number")
	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d: %s", w.Code, w.Body.String())
	}
}

// TestListDevices_RequestCountIncrementsOnUpsert verifies that re-upserting
// the same IP+agent increments the request count.
func TestListDevices_RequestCountIncrementsOnUpsert(t *testing.T) {
	sqlDB, queries := newDevicesTestDB(t)
	engine := newDevicesEngine(t, sqlDB, queries)
	ctx := context.Background()

	params := db.UpsertConnectedDeviceParams{
		IpAddress: "172.16.0.1",
		UserAgent: "curl/7.88",
	}
	queries.UpsertConnectedDevice(ctx, params)
	queries.UpsertConnectedDevice(ctx, params)
	queries.UpsertConnectedDevice(ctx, params)

	w := doDeviceReq(engine, http.MethodGet, "/api/v0/devices")
	var devices []v0_devices.ConnectedDeviceJSON
	json.Unmarshal(w.Body.Bytes(), &devices)
	if len(devices) != 1 {
		t.Fatalf("expected 1 device, got %d", len(devices))
	}
	if devices[0].RequestCount < 3 {
		t.Errorf("RequestCount = %d; want >= 3", devices[0].RequestCount)
	}
}
