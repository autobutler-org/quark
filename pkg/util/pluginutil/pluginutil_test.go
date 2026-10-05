package pluginutil

import (
	"errors"
	"testing"
)

func TestInstallListUninstall(t *testing.T) {
	t.Setenv("HOME", t.TempDir())

	if err := InstallPlugin("../etc"); err == nil {
		t.Fatal("a path-traversal id was accepted")
	}
	if err := InstallPlugin("nope"); !errors.Is(err, ErrNotInCatalog) {
		t.Fatalf("unknown id: got %v, want ErrNotInCatalog", err)
	}
	if err := UninstallPlugin("hello"); !errors.Is(err, ErrNotInstalled) {
		t.Fatalf("uninstall before install: got %v, want ErrNotInstalled", err)
	}

	if err := InstallPlugin("hello"); err != nil {
		t.Fatalf("install: %v", err)
	}
	plugins, err := ListPlugins()
	if err != nil || len(plugins) != 1 || plugins[0].ID != "hello" {
		t.Fatalf("after install: plugins=%v err=%v", plugins, err)
	}
	market, err := ListMarketplace()
	if err != nil || len(market) != 1 || !market[0].Installed {
		t.Fatalf("marketplace after install: %v err=%v", market, err)
	}

	if err := UninstallPlugin("hello"); err != nil {
		t.Fatalf("uninstall: %v", err)
	}
	if plugins, _ := ListPlugins(); len(plugins) != 0 {
		t.Fatalf("after uninstall: %v", plugins)
	}
}
