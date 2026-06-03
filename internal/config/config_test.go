package config

import "testing"

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
