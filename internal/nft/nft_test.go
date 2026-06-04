package nft

import (
	"strings"
	"testing"

	"github.com/leconio/knockport/internal/config"
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

func TestParseInputBaseChainsFindsLaterDrop(t *testing.T) {
	ruleset := `table inet knockgate {
	chain input {
		type filter hook input priority mangle; policy accept;
		tcp dport 23456 drop # handle 1
	}
}
table inet host_filter {
	chain input {
		type filter hook input priority filter; policy drop;
		ct state established,related accept # handle 2
		tcp dport 29312 accept # handle 3
	}
}`
	chains := parseInputBaseChains(ruleset)
	if len(chains) != 2 {
		t.Fatalf("expected 2 input chains, got %d: %#v", len(chains), chains)
	}
	if chains[1].priority != 0 || chains[1].policy != "drop" {
		t.Fatalf("unexpected later chain: %#v", chains[1])
	}
	if chainAcceptsPort(chains[1], 23456, "tcp") {
		t.Fatal("chain must not accept unlisted protected port")
	}
}

func TestChainAcceptsPortSetAndRange(t *testing.T) {
	chain := inputBaseChain{
		priority: 0,
		policy:   "drop",
		rules: []string{
			"tcp dport { 80, 443, 23456 } accept",
			"udp dport 30000-30010 accept",
		},
	}
	if !chainAcceptsPort(chain, 23456, "tcp") {
		t.Fatal("expected tcp set to accept 23456")
	}
	if !chainAcceptsPort(chain, 30005, "udp") {
		t.Fatal("expected udp range to accept 30005")
	}
	if chainAcceptsPort(chain, 30005, "tcp") {
		t.Fatal("tcp must not match udp range")
	}
}

func TestChainHookDefaultsToPrerouting(t *testing.T) {
	hook := chainHook(config.Config{ProtectHook: config.HookPrerouting})
	if hook.chainName != "prerouting" || hook.hookName != "prerouting" {
		t.Fatalf("unexpected hook: %#v", hook)
	}
}

func TestProtectedAddRulesUsesSelectedChain(t *testing.T) {
	rules := protectedAddRules("prerouting", []int{5432}, nil)
	if !strings.Contains(rules, "add rule inet knockgate prerouting ip saddr @knock_allow_temp_v4 tcp dport 5432 accept") {
		t.Fatalf("missing prerouting accept rule:\n%s", rules)
	}
	if strings.Contains(rules, " knockgate input ") {
		t.Fatalf("must not write input rules when prerouting is selected:\n%s", rules)
	}
}
