package install

import (
	"encoding/xml"
	"testing"
)

func TestDNSSDServiceContent(t *testing.T) {
	var group struct {
		Name struct {
			ReplaceWildcards string `xml:"replace-wildcards,attr"`
			Value            string `xml:",chardata"`
		} `xml:"name"`
		Service struct {
			Type string   `xml:"type"`
			Port int      `xml:"port"`
			TXT  []string `xml:"txt-record"`
		} `xml:"service"`
	}
	if err := xml.Unmarshal([]byte(dnsSDServiceContent), &group); err != nil {
		t.Fatalf("service file is not valid XML: %v", err)
	}
	if group.Name.Value != "Quark on %h" || group.Name.ReplaceWildcards != "yes" {
		t.Errorf("name = %q replace-wildcards=%q, want %q with wildcards replaced", group.Name.Value, group.Name.ReplaceWildcards, "Quark on %h")
	}
	if group.Service.Type != "_quark._tcp" || group.Service.Port != 443 {
		t.Errorf("service = %s:%d, want _quark._tcp:443", group.Service.Type, group.Service.Port)
	}
	if len(group.Service.TXT) != 0 {
		t.Errorf("txt records = %q, want none", group.Service.TXT)
	}
}
