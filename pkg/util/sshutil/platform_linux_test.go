//go:build linux

package sshutil

import (
	"os"
	"path/filepath"
	"testing"
)

func TestHasLoginShell(t *testing.T) {
	path := filepath.Join(t.TempDir(), "passwd")
	content := "root:x:0:0:root:/root:/bin/bash\n" +
		"quark:x:999:999:Quark service account:/home/quark:/usr/sbin/nologin\n" +
		"shell:x:1000:1000::/home/shell:/bin/bash\n" +
		"stuck:x:1001:1001::/home/stuck:/bin/false\n" +
		"plain:x:1002:1002::/home/plain:\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	for user, want := range map[string]bool{"quark": false, "shell": true, "stuck": false, "plain": true, "absent": false} {
		if got := hasLoginShell(path, user); got != want {
			t.Errorf("hasLoginShell(%s) = %v, want %v", user, got, want)
		}
	}
}
