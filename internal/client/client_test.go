package client

import (
	"encoding/base64"
	"testing"
	"time"
)

func TestParseImport(t *testing.T) {
	secret := base64.RawURLEncoding.EncodeToString([]byte("12345678901234567890123456789012"))
	raw := "knockgate://import/v1?host=203.0.113.10&knock_ports=10001%2C10002%2C10003&protected_ports=5432%2C9092%2Fudp&secret=" + secret + "&seq_timeout=10&hmac_window=60"
	imp, err := ParseImport(raw)
	if err != nil {
		t.Fatal(err)
	}
	if imp.Host != "203.0.113.10" {
		t.Fatalf("host = %s", imp.Host)
	}
	if len(imp.KnockPorts) != 3 || imp.KnockPorts[2] != 10003 {
		t.Fatalf("knock ports = %#v", imp.KnockPorts)
	}
	if len(imp.ProtectedPorts) != 2 || imp.ProtectedPorts[1].Proto != "udp" {
		t.Fatalf("protected ports = %#v", imp.ProtectedPorts)
	}
}

func TestParseFlexibleDuration(t *testing.T) {
	tests := map[string]time.Duration{
		"3":     3 * time.Second,
		"0.25":  250 * time.Millisecond,
		"150ms": 150 * time.Millisecond,
	}
	for input, want := range tests {
		got, err := parseFlexibleDuration(input)
		if err != nil {
			t.Fatalf("%s: %v", input, err)
		}
		if got != want {
			t.Fatalf("%s = %s, want %s", input, got, want)
		}
	}
}

func TestShouldRefreshKnock(t *testing.T) {
	now := time.Unix(2000, 0)

	should, reason, _ := shouldRefreshKnock("8.8.8.8", "1.1.1.1", now, "12h", now)
	if !should || reason == "" {
		t.Fatal("expected IP change to refresh")
	}

	should, _, next := shouldRefreshKnock("8.8.8.8", "8.8.8.8", now.Add(-time.Hour), "12h", now)
	if should {
		t.Fatal("did not expect refresh before threshold")
	}
	if next <= 0 {
		t.Fatal("expected next refresh duration")
	}

	should, reason, _ = shouldRefreshKnock("8.8.8.8", "8.8.8.8", now.Add(-12*time.Hour), "12h", now)
	if !should || reason == "" {
		t.Fatal("expected timeout refresh")
	}

	should, _, next = shouldRefreshKnock("8.8.8.8", "8.8.8.8", now.Add(-24*time.Hour), "0", now)
	if should || next != 0 {
		t.Fatal("permanent open_timeout should not refresh unchanged IP")
	}
}

func TestParseOpenTimeout(t *testing.T) {
	d, permanent, err := parseOpenTimeout("12h")
	if err != nil || permanent || d != 12*time.Hour {
		t.Fatalf("12h parsed as d=%s permanent=%v err=%v", d, permanent, err)
	}
	d, permanent, err = parseOpenTimeout("1d")
	if err != nil || permanent || d != 24*time.Hour {
		t.Fatalf("1d parsed as d=%s permanent=%v err=%v", d, permanent, err)
	}
	d, permanent, err = parseOpenTimeout("0")
	if err != nil || !permanent || d != 0 {
		t.Fatalf("0 parsed as d=%s permanent=%v err=%v", d, permanent, err)
	}
}
