package install

import "os"

const (
	// avahiServicesDir is where avahi-daemon reads static service files. The
	// daemon watches it with inotify and reloads on its own, so nothing needs a
	// restart after a write.
	avahiServicesDir = "/etc/avahi/services"
	// dnsSDServicePath replaces the file the OS image used to write (#2312).
	dnsSDServicePath = avahiServicesDir + "/quark-dns-sd.service"
)

// dnsSDServiceContent advertises _quark._tcp for the app to browse (#2312).
// Avahi substitutes %h with the hostname, so a rename needs no rewrite. It
// carries no TXT record: nothing reads one, and the app asks a Quark for its
// version once connected.
const dnsSDServiceContent = `<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<!-- Written by quark install. Changes are overwritten on the next install. -->
<service-group>
  <name replace-wildcards="yes">Quark on %h</name>
  <service>
    <type>_quark._tcp</type>
    <port>443</port>
  </service>
</service-group>
`

// installDNSSDService writes the service file when Avahi is installed.
// Without it there is nothing to advertise through.
func installDNSSDService() error {
	if _, err := os.Stat(avahiServicesDir); err != nil {
		return nil
	}
	_, err := writeRootFileIfChanged(dnsSDServicePath, dnsSDServiceContent, 0o644)
	return err
}
