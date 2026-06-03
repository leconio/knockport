package nft

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
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
	resetTableObjects()
	return applyObjects(cfg)
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

func resetTableObjects() {
	_, _ = Run("nft", "flush", "chain", Family, Table, "input")
	_, _ = Run("nft", "delete", "chain", Family, Table, "input")
	_, _ = Run("nft", "delete", "set", Family, Table, Set)
}

func applyObjects(cfg config.Config) error {
	tcpPorts := config.ProtectedTCPPorts(cfg.ProtectedPorts)
	udpPorts := config.ProtectedUDPPorts(cfg.ProtectedPorts)
	data := fmt.Sprintf(`#!/usr/sbin/nft -f

add set %s %s %s {
    type ipv4_addr
    flags timeout
}

add chain %s %s input {
    type filter hook input priority -150; policy accept;
}

%s
`, Family, Table, Set, Family, Table, protectedAddRules(tcpPorts, udpPorts))
	if err := os.WriteFile(config.NFTApplyFile, []byte(data), 0600); err != nil {
		return err
	}
	_, err := Run("nft", "-f", config.NFTApplyFile)
	return err
}

func AddAllow(ip string, timeout string) error {
	// nft set 的 key 唯一；先删再加可以在旧版 nftables 上刷新 timeout。
	_, _ = Run("nft", "delete", "element", Family, Table, Set, "{", ip, "}")
	_, err := Run("nft", "add", "element", Family, Table, Set, "{", ip, "timeout", timeout, "}")
	return err
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
