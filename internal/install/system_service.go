package install

import (
	"os"
	"runtime"
)

const (
	serviceUserName  = "quark"
	serviceGroupName = "quark"
	serviceDataDir   = "/var/lib/quark"

	// serviceLoginShell lets the service account log in over SSH once an admin
	// turns SSH access on and allows a key or sets a password (#2131). Until
	// then the account has neither, so the shell alone lets nobody in.
	serviceLoginShell = "/bin/bash"

	// serviceBinDir holds the installed binary, and is group-owned by the
	// service account so the service can replace its own binary in place.
	//
	// The binary used to live directly in /usr/local/bin, which is root:root
	// 0755. replaceSelf creates its temp file in the directory holding the
	// executable — correctly, so the final rename is atomic and same-filesystem
	// — so an unprivileged service could never complete an update there
	// (#1609). legacyBinPath is kept as a symlink into this directory so
	// `quark` stays on PATH and existing unit files keep resolving.
	serviceBinDir  = "/opt/quark/bin"
	serviceBinPath = serviceBinDir + "/quark"
	legacyBinPath  = "/usr/local/bin/quark"

	// serviceBinDirMode is setgid (2775) so anything created in the directory
	// inherits the quark group, keeping the directory writable across updates.
	serviceBinDirMode = os.ModeSetgid | 0775
	binaryMode        = 0755

	systemdServiceName = "quark.service"

	// systemdServiceContent grants CAP_NET_BIND_SERVICE as an ambient
	// capability and deliberately leaves the bounding set alone. The bounding
	// set also caps what a setuid-root program started by the service gets,
	// so restricting it to CAP_NET_BIND_SERVICE left `sudo` without the
	// capabilities to switch groups or mount, and every `sudo mount` failed
	// (#2115).
	systemdServiceContent = `[Unit]
Description=Quark Service
After=network.target

[Service]
User=quark
Group=quark
ExecStart=/opt/quark/bin/quark serve
Environment="PORT=80"
Environment="HTTPS_PORT=443"
Environment="GIN_MODE=release"
AmbientCapabilities=CAP_NET_BIND_SERVICE
Restart=always
StandardOutput=append:/var/log/quark.app
StandardError=append:/var/log/quark.err

[Install]
WantedBy=multi-user.target`
	plistServiceName    = "ai.quark.plist"
	plistServiceContent = `<!-- /Library/LaunchDaemons/ -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.quark</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/quark</string>
        <string>serve</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key>
        <string>80</string>
        <key>HTTPS_PORT</key>
        <string>443</string>
        <key>GIN_MODE</key>
        <string>release</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/quark.app</string>
    <key>StandardErrorPath</key>
    <string>/var/log/quark.err</string>
</dict>
</plist>`
)

func buildServiceFile() string {
	switch runtime.GOOS {
	case "linux":
		return systemdServiceContent
	case "darwin": // coverage: ignore - Not run in CI
		return plistServiceContent
	default:
		panic("unsupported operating system")
	}
}
