package nft

import (
	"strings"
	"testing"
)

func TestProtectedRulesRenderTCPAndUDP(t *testing.T) {
	rules := protectedRules([]int{2345, 3456}, []int{2345, 4567})
	wants := []string{
		"ip saddr @knock_allow_temp_v4 tcp dport { 2345, 3456 } accept",
		"tcp dport { 2345, 3456 } drop",
		"ip saddr @knock_allow_temp_v4 udp dport { 2345, 4567 } accept",
		"udp dport { 2345, 4567 } drop",
	}
	for _, want := range wants {
		if !strings.Contains(rules, want) {
			t.Fatalf("rules missing %q:\n%s", want, rules)
		}
	}
}

func TestProtectedRulesCanRenderUDPOnly(t *testing.T) {
	rules := protectedRules(nil, []int{2345})
	if strings.Contains(rules, "tcp dport") {
		t.Fatalf("unexpected tcp rule:\n%s", rules)
	}
	if !strings.Contains(rules, "udp dport 2345 drop") {
		t.Fatalf("missing udp drop rule:\n%s", rules)
	}
}
