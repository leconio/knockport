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
