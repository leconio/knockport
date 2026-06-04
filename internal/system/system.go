package system

import (
	"archive/tar"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"

	"github.com/leconio/knockport/internal/config"
	"github.com/leconio/knockport/internal/nft"
)

const (
	InstallPath      = "/usr/local/bin/knockgate"
	ServiceFile      = "/etc/systemd/system/knockgate.service"
	LegacyNFTService = "/etc/systemd/system/knockgate-nft.service"
	LegacyKnockdDrop = "/etc/systemd/system/knockd.service.d/override.conf"
	DefaultRepo      = "leconio/knockport"
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

func UpgradeServer(version string) (string, error) {
	arch, err := releaseArch()
	if err != nil {
		return "", err
	}
	asset := fmt.Sprintf("knockgate_linux_%s.tar.gz", arch)
	url := releaseURL(version, asset)
	tmpDir, err := os.MkdirTemp("", "knockgate-upgrade-*")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(tmpDir)
	assetPath := filepath.Join(tmpDir, asset)
	sumPath := assetPath + ".sha256"
	if err := downloadFile(assetPath, url); err != nil {
		return "", err
	}
	if err := downloadFile(sumPath, url+".sha256"); err != nil {
		return "", err
	}
	if err := verifySHA256(assetPath, sumPath); err != nil {
		return "", err
	}
	extracted, err := extractKnockgate(assetPath, tmpDir)
	if err != nil {
		return "", err
	}
	backup := fmt.Sprintf("%s.bak.%s", InstallPath, time.Now().Format("20060102-150405"))
	if _, err := os.Stat(InstallPath); err == nil {
		if err := copyFile(InstallPath, backup, 0755); err != nil {
			return "", err
		}
	}
	next := InstallPath + ".new"
	_ = os.Remove(next)
	if err := copyFile(extracted, next, 0755); err != nil {
		return "", err
	}
	if err := os.Rename(next, InstallPath); err != nil {
		_ = os.Remove(next)
		return "", err
	}
	return backup, nil
}

func releaseArch() (string, error) {
	switch runtime.GOARCH {
	case "amd64", "arm64":
		return runtime.GOARCH, nil
	default:
		return "", fmt.Errorf("不支持的架构：%s", runtime.GOARCH)
	}
}

func releaseURL(version, asset string) string {
	if base := strings.TrimRight(os.Getenv("KNOCKGATE_ASSET_BASE"), "/"); base != "" {
		return base + "/" + asset
	}
	repo := os.Getenv("KNOCKGATE_REPO")
	if repo == "" {
		repo = DefaultRepo
	}
	if version == "" {
		version = os.Getenv("KNOCKGATE_VERSION")
	}
	if version != "" {
		return fmt.Sprintf("https://github.com/%s/releases/download/%s/%s", repo, version, asset)
	}
	return fmt.Sprintf("https://github.com/%s/releases/latest/download/%s", repo, asset)
}

func downloadFile(path, url string) error {
	client := http.Client{Timeout: 60 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("下载失败 %s: HTTP %s", url, resp.Status)
	}
	out, err := os.OpenFile(path, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, resp.Body)
	return err
}

func verifySHA256(assetPath, sumPath string) error {
	data, err := os.ReadFile(sumPath)
	if err != nil {
		return err
	}
	fields := strings.Fields(string(data))
	if len(fields) == 0 {
		return errors.New("sha256 文件为空")
	}
	want := strings.ToLower(fields[0])
	in, err := os.Open(assetPath)
	if err != nil {
		return err
	}
	defer in.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, in); err != nil {
		return err
	}
	got := hex.EncodeToString(hash.Sum(nil))
	if got != want {
		return fmt.Errorf("sha256 校验失败：got %s want %s", got, want)
	}
	return nil
}

func extractKnockgate(assetPath, tmpDir string) (string, error) {
	in, err := os.Open(assetPath)
	if err != nil {
		return "", err
	}
	defer in.Close()
	gz, err := gzip.NewReader(in)
	if err != nil {
		return "", err
	}
	defer gz.Close()
	tr := tar.NewReader(gz)
	for {
		header, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return "", err
		}
		if header.Typeflag != tar.TypeReg || filepath.Base(header.Name) != "knockgate" {
			continue
		}
		outPath := filepath.Join(tmpDir, "knockgate.new")
		out, err := os.OpenFile(outPath, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0755)
		if err != nil {
			return "", err
		}
		if _, err := io.Copy(out, tr); err != nil {
			_ = out.Close()
			return "", err
		}
		if err := out.Close(); err != nil {
			return "", err
		}
		return outPath, nil
	}
	return "", errors.New("release 包中未找到 knockgate 二进制")
}

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		_ = out.Close()
		return err
	}
	return out.Close()
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
