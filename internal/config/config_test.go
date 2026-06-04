package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestParseProtectedPortsProtocols(t *testing.T) {
	ports, err := ParseProtectedPorts("2345,3456/tcp,4567/udp")
	if err != nil {
		t.Fatal(err)
	}
	if got := JoinProtectedPorts(ports); got != "2345,3456/tcp,4567/udp" {
		t.Fatalf("JoinProtectedPorts() = %q", got)
	}
	if got := JoinPorts(ProtectedTCPPorts(ports)); got != "2345,3456" {
		t.Fatalf("ProtectedTCPPorts() = %q", got)
	}
	if got := JoinPorts(ProtectedUDPPorts(ports)); got != "2345,4567" {
		t.Fatalf("ProtectedUDPPorts() = %q", got)
	}
}

func TestParseProtectedPortsRejectsInvalidProtocol(t *testing.T) {
	if _, err := ParseProtectedPorts("2345/sctp"); err == nil {
		t.Fatal("expected invalid protocol to fail")
	}
}

func TestParseFileUnquotesValues(t *testing.T) {
	path := filepath.Join(t.TempDir(), "knockgate.conf")
	if err := os.WriteFile(path, []byte("INTERFACE=\"eth0\"\nOPEN_TIMEOUT=\"12h\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	values, err := ParseFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if values["INTERFACE"] != "eth0" || values["OPEN_TIMEOUT"] != "12h" {
		t.Fatalf("unexpected values: %#v", values)
	}
}

func TestValidateRejectsUnsafeInterface(t *testing.T) {
	cfg := Config{
		ProtectedPorts:    []ProtectedPort{{Port: 5432, Proto: ProtoBoth}},
		KnockPorts:        []int{30001, 30002},
		OpenTimeout:       "12h",
		SeqTimeoutSeconds: 10,
		HMACWindowSeconds: 60,
		Secret:            "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI",
		Interface:         "eth0\"\nBAD=1",
	}
	if err := Validate(cfg); err == nil {
		t.Fatal("expected unsafe interface to fail")
	}
}
