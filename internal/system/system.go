package system

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/leconio/knockport/internal/config"
	"github.com/leconio/knockport/internal/nft"
)

const (
	InstallPath      = "/usr/local/bin/knockgate"
	ServiceFile      = "/etc/systemd/system/knockgate.service"
	LegacyNFTService = "/etc/systemd/system/knockgate-nft.service"
	LegacyKnockdDrop = "/etc/systemd/system/knockd.service.d/override.conf"
)

func RequireRoot() error {
	if os.Geteuid() != 0 {
		return errors.New("请使用 root 权限运行")
	}
	return nil
}

// InstallPackages 只安装 Go 版需要的系统组件，不再安装 knockd。
func InstallPackages() error {
	missing := missingCommands()
	missing = append(missing, libpcapPackages()...)
	optional := optionalPackages()
	if len(missing) == 0 {
		installOptional(optional)
		return nil
	}
	family, err := packageFamily()
	if err != nil {
		return err
	}
	switch family {
	case "apt":
		if _, err := nft.Run("apt-get", append([]string{"install", "-y"}, missing...)...); err != nil {
			if _, updateErr := nft.Run("apt-get", "update"); updateErr != nil {
				return updateErr
			}
			if _, err = nft.Run("apt-get", append([]string{"install", "-y"}, missing...)...); err != nil {
				return err
			}
		}
	case "dnf":
		if err := installDNF(missing); err != nil {
			return err
		}
	case "pacman":
		_, err = nft.Run("pacman", append([]string{"-Sy", "--noconfirm"}, missing...)...)
		if err != nil {
			return err
		}
	default:
		return fmt.Errorf("不支持的包管理器：%s", family)
	}
	installOptional(optional)
	return nil
}

func missingCommands() []string {
	need := map[string]string{
		"nft": "nftables",
		"ip":  "iproute2",
	}
	var missing []string
	for cmd, pkg := range need {
		if _, err := exec.LookPath(cmd); err != nil {
			missing = append(missing, pkg)
		}
	}
	return missing
}

func optionalPackages() []string {
	if _, err := exec.LookPath("qrencode"); err == nil {
		return nil
	}
	return []string{"qrencode"}
}

func installOptional(pkgs []string) {
	if len(pkgs) == 0 {
		return
	}
	family, err := packageFamily()
	if err != nil {
		return
	}
	switch family {
	case "apt":
		_, _ = nft.Run("apt-get", append([]string{"install", "-y"}, pkgs...)...)
	case "dnf":
		_ = installDNF(pkgs)
	case "pacman":
		_, _ = nft.Run("pacman", append([]string{"-S", "--noconfirm"}, pkgs...)...)
	}
}

func libpcapPackages() []string {
	family, err := packageFamily()
	if err != nil {
		return nil
	}
	switch family {
	case "apt":
		return []string{"libpcap0.8"}
	case "dnf":
		return []string{"libpcap"}
	case "pacman":
		return []string{"libpcap"}
	default:
		return nil
	}
}

func installDNF(pkgs []string) error {
	var mapped []string
	for _, pkg := range pkgs {
		if pkg == "iproute2" {
			pkg = "iproute"
		}
		mapped = append(mapped, pkg)
	}
	_, err := nft.Run("dnf", append([]string{"install", "-y"}, mapped...)...)
	return err
}

func packageFamily() (string, error) {
	data, err := os.ReadFile("/etc/os-release")
	if err != nil {
		return "", errors.New("不支持的 Linux 发行版：缺少 /etc/os-release")
	}
	text := string(data)
	if strings.Contains(text, "ID=ubuntu") || strings.Contains(text, "ID=debian") || strings.Contains(text, "ID_LIKE=debian") {
		return "apt", nil
	}
	if strings.Contains(text, "ID=fedora") || strings.Contains(text, "ID=rocky") || strings.Contains(text, "ID=almalinux") || strings.Contains(text, "ID=centos") || strings.Contains(text, "ID_LIKE=rhel") || strings.Contains(text, "ID_LIKE=\"rhel") {
		return "dnf", nil
	}
	if strings.Contains(text, "ID=arch") || strings.Contains(text, "ID_LIKE=arch") {
		return "pacman", nil
	}
	return "", fmt.Errorf("不支持的 Linux 发行版：\n%s", text)
}

func InstallSelf() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	src, _ := filepath.EvalSymlinks(exe)
	dst, _ := filepath.EvalSymlinks(InstallPath)
	if src == dst {
		return nil
	}
	in, err := os.Open(exe)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(InstallPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0755)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}

func WriteService() error {
	data := fmt.Sprintf(`[Unit]
Description=KnockGate Go HMAC pcap knock service
Documentation=https://github.com/leconio/knockport
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%s serve
Restart=always
RestartSec=2s
TimeoutStopSec=5s
AmbientCapabilities=CAP_NET_RAW CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_ADMIN
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
`, InstallPath)
	return os.WriteFile(ServiceFile, []byte(data), 0644)
}

func CleanupLegacy() {
	_ = Systemctl("disable", "--now", "knockd.service")
	_ = Systemctl("disable", "--now", "knockgate-nft.service")
	_ = os.Remove(LegacyNFTService)
	_ = os.Remove(LegacyKnockdDrop)
}

func WriteReadme() error {
	data := `KnockGate Go
============

当前安装使用 Go + libpcap 抓包实现 HMAC UDP 顺序敲门。

它只管理 table inet knockgate，不修改 SSH 端口规则，也不重写 /etc/nftables.conf。
KnockGate 不能绕过其他后续防火墙 drop；原防火墙仍需允许已放行来源访问保护服务。
`
	return os.WriteFile(config.ReadmeFile, []byte(data), 0644)
}

func Systemctl(args ...string) error {
	_, err := nft.Run("systemctl", args...)
	return err
}

func Stream(name string, args ...string) error {
	_, err := nft.Stream(name, args...)
	return err
}
