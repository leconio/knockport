package nft

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"

	"github.com/leconio/knockport/internal/config"
)

const (
	Family = "inet"
	Table  = "knockgate"
	Set    = "knock_allow_temp_v4"
)

var ErrTableMissing = errors.New("knockgate nft table missing")

type TakeoverIssue struct {
	Port   int
	Proto  config.Proto
	Reason string
}

func (issue TakeoverIssue) String() string {
	proto := string(issue.Proto)
	if proto == "" {
		proto = string(config.ProtoBoth)
	}
	return fmt.Sprintf("%d/%s: %s", issue.Port, proto, issue.Reason)
}

// WriteConfig 只渲染 KnockGate 自己的 table，不写 /etc/nftables.conf。
func WriteConfig(cfg config.Config) error {
	if err := os.MkdirAll(config.Dir, 0700); err != nil {
		return err
	}
	tcpPorts := config.ProtectedTCPPorts(cfg.ProtectedPorts)
	udpPorts := config.ProtectedUDPPorts(cfg.ProtectedPorts)
	rules := protectedRules(tcpPorts, udpPorts)
	data := fmt.Sprintf(`#!/usr/sbin/nft -f

# 由 KnockGate Go 管理。只定义 table inet knockgate，不修改系统原防火墙。

table %s %s {
    set %s {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority -150; policy accept;

%s
    }
}
`, Family, Table, Set, rules)
	return os.WriteFile(config.NFTFile, []byte(data), 0600)
}

func Apply(cfg config.Config) error {
	if _, err := exec.LookPath("nft"); err != nil {
		return errors.New("未找到 nft 命令，请安装 nftables")
	}
	if err := WriteConfig(cfg); err != nil {
		return err
	}
	if err := ensureTable(); err != nil {
		return err
	}
	return applyObjects(cfg)
}

func CheckInputTakeover(cfg config.Config) ([]TakeoverIssue, error) {
	if _, err := exec.LookPath("nft"); err != nil {
		return nil, errors.New("未找到 nft 命令，请安装 nftables")
	}
	out, err := Run("nft", "-a", "list", "ruleset")
	if err != nil {
		return nil, err
	}
	chains := parseInputBaseChains(out)
	if len(chains) == 0 {
		return nil, nil
	}
	var laterDropChains []inputBaseChain
	for _, chain := range chains {
		if chain.priority > -150 && chain.policy == "drop" {
			laterDropChains = append(laterDropChains, chain)
		}
	}
	if len(laterDropChains) == 0 {
		return nil, nil
	}
	var issues []TakeoverIssue
	for _, protected := range cfg.ProtectedPorts {
		protos := []config.Proto{protected.Proto}
		if protected.Proto == config.ProtoBoth {
			protos = []config.Proto{config.ProtoTCP, config.ProtoUDP}
		}
		for _, proto := range protos {
			if !acceptedByAnyInputChain(laterDropChains, protected.Port, proto) {
				issues = append(issues, TakeoverIssue{
					Port:   protected.Port,
					Proto:  proto,
					Reason: "后续 input 默认 drop 防火墙没有显式放行该端口；KnockGate 放行后仍可能被原防火墙丢弃。请换一个原防火墙已允许的保护端口，或先在原防火墙放行该端口。",
				})
			}
		}
	}
	return issues, nil
}

func ensureTable() error {
	if _, err := Run("nft", "add", "table", Family, Table); err == nil {
		return nil
	} else if strings.Contains(strings.ToLower(err.Error()), "file exists") {
		return nil
	} else {
		return err
	}
}

func applyObjects(cfg config.Config) error {
	tcpPorts := config.ProtectedTCPPorts(cfg.ProtectedPorts)
	udpPorts := config.ProtectedUDPPorts(cfg.ProtectedPorts)
	var setup []string
	if objectExists("chain", "input") {
		setup = append(setup,
			fmt.Sprintf("flush chain %s %s input", Family, Table),
			fmt.Sprintf("delete chain %s %s input", Family, Table),
		)
	}
	if !objectExists("set", Set) {
		setup = append(setup, fmt.Sprintf(`add set %s %s %s {
    type ipv4_addr
    flags timeout
}`, Family, Table, Set))
	}
	data := fmt.Sprintf(`#!/usr/sbin/nft -f

%s

add chain %s %s input {
    type filter hook input priority -150; policy accept;
}

%s
`, strings.Join(setup, "\n"), Family, Table, protectedAddRules(tcpPorts, udpPorts))
	if err := os.WriteFile(config.NFTApplyFile, []byte(data), 0600); err != nil {
		return err
	}
	_, err := Run("nft", "-f", config.NFTApplyFile)
	return err
}

func objectExists(kind, name string) bool {
	var args []string
	switch kind {
	case "chain":
		args = []string{"list", "chain", Family, Table, name}
	case "set":
		args = []string{"list", "set", Family, Table, name}
	default:
		return false
	}
	_, err := Run("nft", args...)
	return err == nil
}

func AddAllow(ip string, timeout string, cfgs ...config.Config) error {
	// nft set 的 key 唯一；先删再加可以在旧版 nftables 上刷新 timeout。
	_, _ = Run("nft", "delete", "element", Family, Table, Set, "{", ip, "}")
	_, err := Run("nft", "add", "element", Family, Table, Set, "{", ip, "timeout", timeout, "}")
	if err != nil && len(cfgs) > 0 && isMissingKnockGateObject(err) {
		if applyErr := Apply(cfgs[0]); applyErr != nil {
			return applyErr
		}
		_, _ = Run("nft", "delete", "element", Family, Table, Set, "{", ip, "}")
		_, err = Run("nft", "add", "element", Family, Table, Set, "{", ip, "timeout", timeout, "}")
	}
	return err
}

func isMissingKnockGateObject(err error) bool {
	if err == nil {
		return false
	}
	text := strings.ToLower(err.Error())
	return strings.Contains(text, "no such file or directory") ||
		strings.Contains(text, "does not exist") ||
		strings.Contains(text, "could not process rule")
}

func FlushAllowlist() error {
	_, err := Run("nft", "flush", "set", Family, Table, Set)
	return err
}

func ClearTable() error {
	_, err := Run("nft", "delete", "table", Family, Table)
	return err
}

func ShowTable() error {
	out, err := Run("nft", "list", "table", Family, Table)
	if err != nil {
		fmt.Println("KnockGate nft 表当前不存在。请运行：sudo knockgate update")
		fmt.Println("KnockGate nft table is missing. Run: sudo knockgate update")
		return ErrTableMissing
	}
	fmt.Print(out)
	return nil
}

func ShowAllowlist() error {
	out, err := Run("nft", "list", "set", Family, Table, Set)
	if err != nil {
		fmt.Println("KnockGate 临时白名单当前不存在。请运行：sudo knockgate update")
		fmt.Println("KnockGate temporary allowlist is missing. Run: sudo knockgate update")
		return ErrTableMissing
	}
	fmt.Print(out)
	return nil
}

func Run(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return string(out), fmt.Errorf("%s %s 失败：%w\n%s", name, strings.Join(args, " "), err, string(out))
	}
	return string(out), nil
}

func Stream(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return "", cmd.Run()
}

func protectedRules(tcpPorts, udpPorts []int) string {
	var lines []string
	if len(tcpPorts) > 0 {
		expr := portExpr(tcpPorts)
		lines = append(lines,
			"        # TCP 保护端口：已通过敲门来源放行，其他来源丢弃。",
			fmt.Sprintf("        ip saddr @%s tcp dport %s accept", Set, expr),
			fmt.Sprintf("        tcp dport %s drop", expr),
		)
	}
	if len(udpPorts) > 0 {
		expr := portExpr(udpPorts)
		lines = append(lines,
			"        # UDP 保护端口：已通过敲门来源放行，其他来源丢弃。",
			fmt.Sprintf("        ip saddr @%s udp dport %s accept", Set, expr),
			fmt.Sprintf("        udp dport %s drop", expr),
		)
	}
	return strings.Join(lines, "\n")
}

func protectedAddRules(tcpPorts, udpPorts []int) string {
	var lines []string
	if len(tcpPorts) > 0 {
		expr := portExpr(tcpPorts)
		lines = append(lines,
			fmt.Sprintf("add rule %s %s input ip saddr @%s tcp dport %s accept", Family, Table, Set, expr),
			fmt.Sprintf("add rule %s %s input tcp dport %s drop", Family, Table, expr),
		)
	}
	if len(udpPorts) > 0 {
		expr := portExpr(udpPorts)
		lines = append(lines,
			fmt.Sprintf("add rule %s %s input ip saddr @%s udp dport %s accept", Family, Table, Set, expr),
			fmt.Sprintf("add rule %s %s input udp dport %s drop", Family, Table, expr),
		)
	}
	return strings.Join(lines, "\n")
}

type inputBaseChain struct {
	name      string
	priority  int
	policy    string
	inputHook bool
	rules     []string
}

func parseInputBaseChains(ruleset string) []inputBaseChain {
	var chains []inputBaseChain
	var current *inputBaseChain
	depth := 0
	for _, raw := range strings.Split(ruleset, "\n") {
		line := strings.TrimSpace(stripHandle(raw))
		if current == nil {
			if strings.HasPrefix(line, "chain ") {
				name := strings.Fields(line)
				if len(name) >= 2 {
					current = &inputBaseChain{name: name[1], priority: 0, policy: "accept"}
					depth = strings.Count(line, "{") - strings.Count(line, "}")
				}
			}
			continue
		}
		depth += strings.Count(line, "{") - strings.Count(line, "}")
		if strings.Contains(line, "type filter hook input") {
			current.inputHook = true
			if priority, ok := parsePriority(line); ok {
				current.priority = priority
			}
			if policy, ok := parsePolicy(line); ok {
				current.policy = policy
			}
		} else if line != "" && line != "}" {
			current.rules = append(current.rules, line)
		}
		if depth <= 0 {
			if current.inputHook {
				chains = append(chains, *current)
			}
			current = nil
		}
	}
	return chains
}

func stripHandle(line string) string {
	if idx := strings.Index(line, "# handle"); idx >= 0 {
		return strings.TrimSpace(line[:idx])
	}
	return line
}

func parsePriority(line string) (int, bool) {
	matches := regexp.MustCompile(`priority\s+([^; ]+)`).FindStringSubmatch(line)
	if len(matches) != 2 {
		return 0, false
	}
	switch matches[1] {
	case "raw":
		return -300, true
	case "mangle":
		return -150, true
	case "dstnat":
		return -100, true
	case "filter":
		return 0, true
	case "security":
		return 50, true
	case "srcnat":
		return 100, true
	default:
		value, err := strconv.Atoi(matches[1])
		return value, err == nil
	}
}

func parsePolicy(line string) (string, bool) {
	matches := regexp.MustCompile(`policy\s+([a-z]+)`).FindStringSubmatch(line)
	if len(matches) != 2 {
		return "", false
	}
	return strings.ToLower(matches[1]), true
}

func acceptedByAnyInputChain(chains []inputBaseChain, port int, proto config.Proto) bool {
	for _, chain := range chains {
		if chainAcceptsPort(chain, port, proto) {
			return true
		}
	}
	return false
}

func chainAcceptsPort(chain inputBaseChain, port int, proto config.Proto) bool {
	for _, rule := range chain.rules {
		if !strings.Contains(rule, " accept") || strings.Contains(rule, "@"+Set) {
			continue
		}
		if proto != config.ProtoBoth && !strings.Contains(rule, string(proto)+" dport") {
			continue
		}
		if ruleContainsPort(rule, port) {
			return true
		}
	}
	return false
}

func ruleContainsPort(rule string, port int) bool {
	target := strconv.Itoa(port)
	for _, token := range regexp.MustCompile(`[^0-9-]+`).Split(rule, -1) {
		if token == "" {
			continue
		}
		if token == target {
			return true
		}
		if strings.Contains(token, "-") {
			left, right, ok := strings.Cut(token, "-")
			if !ok {
				continue
			}
			start, startErr := strconv.Atoi(left)
			end, endErr := strconv.Atoi(right)
			if startErr == nil && endErr == nil && port >= start && port <= end {
				return true
			}
		}
	}
	return false
}

func portExpr(ports []int) string {
	if len(ports) == 1 {
		return strconv.Itoa(ports[0])
	}
	parts := make([]string, len(ports))
	for i, port := range ports {
		parts[i] = strconv.Itoa(port)
	}
	return "{ " + strings.Join(parts, ", ") + " }"
}
