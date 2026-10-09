package install

const (
	// hostnameHelperCheck is the first half of the root helper behind
	// hostnameutil.HelperPath: it reads the new name and refuses anything but
	// one RFC 1123 label before anything privileged runs. The sudoers entry
	// allows no arguments, so the name comes in on stdin, and the helper checks
	// it itself rather than trusting the service to have. It is its own
	// constant so the tests can run the check without the rename after it.
	hostnameHelperCheck = `#!/bin/sh
# Written by quark install. Changes are overwritten on the next install.
# Renames this Quark to the name on stdin: the system hostname, its line in
# /etc/hosts, and the name Avahi answers to on the network.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
# In the C locale a-z is exactly those 26 letters, and a length is in bytes.
LC_ALL=C
export PATH LC_ALL

invalid() {
	echo "invalid hostname" >&2
	exit 2
}

if [ "$#" -ne 0 ]; then
	echo "usage: $0 < hostname" >&2
	exit 2
fi

name=""
IFS= read -r name || true

# One RFC 1123 label: lowercase letters, digits and hyphens, 1 to 63 long, no
# hyphen at either end. A bare number would be read as an IP address, and
# localhost is taken.
case "$name" in
"" | -* | *- | *[!a-z0-9-]* | localhost) invalid ;;
esac
case "$name" in
*[a-z]*) ;;
*) invalid ;;
esac
[ "${#name}" -le 63 ] || invalid
`

	// hostnameHelperContent is the whole helper. Past the check, $name holds
	// only letters, digits and hyphens, so it is safe inside the sed script.
	hostnameHelperContent = hostnameHelperCheck + `
hostnamectl set-hostname "$name"

# Debian maps the hostname to 127.0.1.1 so it resolves with no network up.
if [ -f /etc/hosts ]; then
	sed -i "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1 $name/" /etc/hosts
fi

# avahi-daemon does not reliably pick up a new hostname by itself. Restarted,
# it answers to <name>.local and re-reads the service file quark install
# wrote, whose %h makes it advertise "Quark on <name>".
if systemctl cat avahi-daemon.service >/dev/null 2>&1; then
	systemctl try-restart avahi-daemon.service
fi
`
)
