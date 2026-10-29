package deputil

import (
	"testing"

	"github.com/autobutler-org/quark/internal/db"
)

func TestNewDependencies(t *testing.T) {
	deps := NewDependencies()
	if deps == nil {
		t.Fatal("NewDependencies() returned nil")
	}

	// Verify initial state
	if deps.Database() != nil {
		t.Error("Expected Database() to be nil initially")
	}

	// These replaced package-level globals, or joined them, so every graph
	// must have them ready without a With* call (#1674).
	if deps.AuthRateLimiter() == nil {
		t.Error("Expected AuthRateLimiter() to be ready")
	}
	if deps.ChatRateLimiter() == nil {
		t.Error("Expected ChatRateLimiter() to be ready")
	}
	if deps.PairDeviceRateLimiter() == nil {
		t.Error("Expected PairDeviceRateLimiter() to be ready")
	}
	if deps.ZipSlots() == nil {
		t.Error("Expected ZipSlots() to be ready")
	}
	if deps.AccessCache() == nil {
		t.Error("Expected AccessCache() to be ready")
	}
}

func TestWithDatabase(t *testing.T) {
	deps := NewDependencies()

	var mockDB *db.DatabaseSqlc

	result := deps.WithDatabase(mockDB)

	if result != deps {
		t.Error("WithDatabase() should return the same Dependencies instance")
	}
	if deps.Database() != mockDB {
		t.Error("Database() did not return the expected database")
	}
}
