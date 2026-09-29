package vaultutil

import (
	"testing"
)

func TestDetectFormat_JSON(t *testing.T) {
	data := []byte(`{"entries": []}`)
	if got := DetectFormat(data); got != "json" {
		t.Errorf("expected json, got %s", got)
	}
	data = []byte(`[{"name": "test"}]`)
	if got := DetectFormat(data); got != "json" {
		t.Errorf("expected json for array, got %s", got)
	}
}

func TestDetectFormat_Bitwarden(t *testing.T) {
	data := []byte("folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n")
	if got := DetectFormat(data); got != "bitwarden" {
		t.Errorf("expected bitwarden, got %s", got)
	}
}

func TestDetectFormat_GenericCSV(t *testing.T) {
	data := []byte("url,username,password\nhttps://example.com,alice,secret\n")
	if got := DetectFormat(data); got != "csv" {
		t.Errorf("expected csv, got %s", got)
	}
}

func TestParseBitwardenCSV(t *testing.T) {
	csv := `folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
Social,,login,GitHub,some notes,,0,https://github.com/login,alice,gh-pass,JBSWY3DPEHPK3PXP
Banking,,login,Chase,,,,https://chase.com,bob,chase-pw,
`
	entries, errs := ParseBitwardenCSV([]byte(csv))
	if len(errs) > 0 {
		t.Errorf("unexpected errors: %v", errs)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}

	gh := entries[0]
	if gh.Name != "GitHub" {
		t.Errorf("name = %q, want GitHub", gh.Name)
	}
	if gh.URL != "https://github.com/login" {
		t.Errorf("url = %q", gh.URL)
	}
	if gh.Username != "alice" {
		t.Errorf("username = %q", gh.Username)
	}
	if gh.Password != "gh-pass" {
		t.Errorf("password = %q", gh.Password)
	}
	if gh.Notes != "some notes" {
		t.Errorf("notes = %q", gh.Notes)
	}
	if gh.TOTPSecret != "JBSWY3DPEHPK3PXP" {
		t.Errorf("totp = %q", gh.TOTPSecret)
	}
	if gh.Folder != "Social" {
		t.Errorf("folder = %q", gh.Folder)
	}
}

func TestParseGenericCSV(t *testing.T) {
	csv := `url,username,password
https://example.com,alice,secret
https://test.com,bob,pass123
`
	entries, errs := ParseGenericCSV([]byte(csv))
	if len(errs) > 0 {
		t.Errorf("unexpected errors: %v", errs)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if entries[0].Name != "example.com" {
		t.Errorf("name should be derived from URL host, got %q", entries[0].Name)
	}
	if entries[0].Username != "alice" {
		t.Errorf("username = %q", entries[0].Username)
	}
}

func TestParseGenericCSV_ChromeFormat(t *testing.T) {
	csv := `name,url,username,password,note
GitHub,https://github.com,alice,gh-pass,my notes
`
	entries, errs := ParseGenericCSV([]byte(csv))
	if len(errs) > 0 {
		t.Errorf("unexpected errors: %v", errs)
	}
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
	if entries[0].Name != "GitHub" {
		t.Errorf("name = %q", entries[0].Name)
	}
	if entries[0].Notes != "my notes" {
		t.Errorf("notes = %q", entries[0].Notes)
	}
}

func TestParseGenericCSV_MissingPassword(t *testing.T) {
	csv := `url,username,password
https://example.com,alice,
`
	entries, errs := ParseGenericCSV([]byte(csv))
	if len(entries) != 0 {
		t.Errorf("expected 0 entries, got %d", len(entries))
	}
	if len(errs) != 1 {
		t.Errorf("expected 1 error, got %d", len(errs))
	}
}

func TestParseQuarkJSON(t *testing.T) {
	j := `{
		"entries": [
			{"name": "GitHub", "url": "https://github.com", "username": "alice", "password": "pw", "folderName": "Dev"},
			{"name": "Gmail", "url": "https://gmail.com", "username": "bob", "password": "gm"}
		],
		"folders": ["Dev"]
	}`
	entries, errs := ParseQuarkJSON([]byte(j))
	if len(errs) > 0 {
		t.Errorf("unexpected errors: %v", errs)
	}
	if len(entries) != 2 {
		t.Fatalf("expected 2 entries, got %d", len(entries))
	}
	if entries[0].Folder != "Dev" {
		t.Errorf("folder = %q, want Dev", entries[0].Folder)
	}
}

func TestParseQuarkJSON_Array(t *testing.T) {
	j := `[{"name": "Test", "url": "https://test.com", "username": "u", "password": "p"}]`
	entries, errs := ParseQuarkJSON([]byte(j))
	if len(errs) > 0 {
		t.Errorf("unexpected errors: %v", errs)
	}
	if len(entries) != 1 {
		t.Fatalf("expected 1 entry, got %d", len(entries))
	}
}

func TestDedupKey(t *testing.T) {
	k1 := dedupKey("GitHub", "github.com")
	k2 := dedupKey("github", "GitHub.com")
	if k1 != k2 {
		t.Error("dedupKey should be case-insensitive")
	}
}

func TestHostFromURL(t *testing.T) {
	tests := []struct{ input, want string }{
		{"https://github.com/login", "github.com"},
		{"http://localhost:8080/path", "localhost"},
		{"", ""},
		{"not a url", ""},
		{"github.com", "github.com"},
		{"github.com/login", "github.com"},
		{"  www.amazon.com  ", "www.amazon.com"},
		{"192.168.1.1", "192.168.1.1"},
		{"https://GitHub.com/login", "github.com"},
	}
	for _, tt := range tests {
		if got := HostFromURL(tt.input); got != tt.want {
			t.Errorf("HostFromURL(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

const protonPassExport = `type,name,url,email,username,password,note,totp,createTime,modifyTime,vault
login,GitHub,"https://github.com/login, https://gist.github.com",alice@example.com,alice,gh-pass,work account,JBSWY3DPEHPK3PXP,1700000000,1700000000,Work
login,Bank,https://bank.example,bob@example.com,,bank-pass,,,1700000000,1700000000,Personal
note,Wi-Fi code,,,,,door code 1234,,1700000000,1700000000,Personal
alias,Newsletter alias,,news@alias.example,,,,,1700000000,1700000000,Personal
creditCard,Visa,,,,,,,1700000000,1700000000,Personal
login,Empty,https://empty.example,,,,,,1700000000,1700000000,Personal
`

const googlePasswordsExport = `name,url,username,password,note
github.com,https://github.com/login,alice,gh-pass,
,https://accounts.example.com/,carol,pw,old laptop
`

func TestDetectFormat_RecognizesProtonPassAndGoogle(t *testing.T) {
	tests := []struct{ name, data, want string }{
		{"proton pass", protonPassExport, FormatProtonPass},
		{"google", googlePasswordsExport, FormatGoogle},
		{"google without note", "name,url,username,password\nx,https://x.example,u,p\n", FormatGoogle},
		{"generic", "title,website,login,pass,extra,more\nx,https://x.example,u,p,,\n", FormatCSV},
	}
	for _, tt := range tests {
		if got := DetectFormat([]byte(tt.data)); got != tt.want {
			t.Errorf("%s: DetectFormat = %q, want %q", tt.name, got, tt.want)
		}
	}
}

func TestParseProtonPassCSV_KeepsLoginsAndCountsTheRest(t *testing.T) {
	entries, errs, ignored := ParseProtonPassCSV([]byte(protonPassExport))

	if ignored != 3 {
		t.Errorf("ignored = %d, want 3 (note, alias, card)", ignored)
	}
	if len(errs) != 1 {
		t.Errorf("errors = %v, want one for the empty login", errs)
	}
	if len(entries) != 2 {
		t.Fatalf("got %d entries, want 2", len(entries))
	}

	github := entries[0]
	if github.URL != "https://github.com/login" {
		t.Errorf("URL = %q, want the first of the list", github.URL)
	}
	if github.Username != "alice" || github.TOTPSecret != "JBSWY3DPEHPK3PXP" || github.Folder != "Work" || github.Notes != "work account" {
		t.Errorf("github entry = %+v", github)
	}

	if bank := entries[1]; bank.Username != "bob@example.com" {
		t.Errorf("bank username = %q, want the email when username is empty", bank.Username)
	}
}

func TestParseGenericCSV_ReadsGooglePasswordManagerExport(t *testing.T) {
	entries, errs := ParseGenericCSV([]byte(googlePasswordsExport))
	if len(errs) != 0 {
		t.Fatalf("errors = %v", errs)
	}
	if len(entries) != 2 {
		t.Fatalf("got %d entries, want 2", len(entries))
	}
	if entries[0].Name != "github.com" || entries[0].Username != "alice" || entries[0].Password != "gh-pass" {
		t.Errorf("first entry = %+v", entries[0])
	}
	if entries[1].Name != "accounts.example.com" || entries[1].Notes != "old laptop" {
		t.Errorf("second entry = %+v, want the host as its name and the note kept", entries[1])
	}
}
