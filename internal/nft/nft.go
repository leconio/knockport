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

// WriteConfig 只渲染 KnockGate 自己的 table，不写 /etc/nftables.conf。
func WriteConfig(cfg config.Config) error {
	if err := os.MkdirAll(config.Dir, 0700); err != nil {
		return err
	}
	protected := portExpr(cfg.ProtectedPorts)
	data := fmt.Sprintf(`#!/usr/sbin/nft -f

# 由 KnockGate Go 管理。只定义 table inet knockgate，不修改系统原防火墙。

table %s %s {
    set %s {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority -150; policy accept;

        # 已通过 HMAC 敲门的来源 IP 可以访问保护端口。
        ip saddr @%s tcp dport %s accept

        # 未通过敲门的来源只丢弃保护端口；其他端口交给原防火墙继续处理。
        tcp dport %s drop
    }
}
`, Family, Table, Set, Set, protected, protected)
	return os.WriteFile(config.NFTFile, []byte(data), 0600)
}

func Apply(cfg config.Config) error {
	if _, err := exec.LookPath("nft"); err != nil {
		return errors.New("未找到 nft 命令，请安装 nftables")
	}
	if err := WriteConfig(cfg); err != nil {
		return err
	}
	_, _ = Run("nft", "delete", "table", Family, Table)
	_, err := Run("nft", "-f", config.NFTFile)
	return err
}

func AddAllow(ip string, timeout string) error {
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
	_, err := Stream("nft", "list", "table", Family, Table)
	return err
}

func ShowAllowlist() error {
	_, err := Stream("nft", "list", "set", Family, Table, Set)
	return err
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
