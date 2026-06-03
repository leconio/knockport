package app

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"os/signal"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"

	"github.com/leconio/knockport/internal/config"
	"github.com/leconio/knockport/internal/knock"
	"github.com/leconio/knockport/internal/nft"
	"github.com/leconio/knockport/internal/system"
	"github.com/leconio/knockport/internal/ui"
)

func Run(args []string) error {
	if len(args) == 0 {
		if os.Geteuid() == 0 {
			return Menu()
		}
		Usage()
		return nil
	}
	switch args[0] {
	case "serve":
		return Serve()
	case "install", "repair":
		return Install()
	case "update":
		return Update()
	case "reset":
		return Reset()
	case "status":
		return Status()
	case "logs":
		return Logs(false)
	case "logs-follow":
		return Logs(true)
	case "allowlist":
		return Allowlist()
	case "allow":
		if len(args) != 2 {
			return errors.New("用法：knockgate allow IPv4")
		}
		return AddAllow(args[1])
	case "flush":
		return FlushAllowlist()
	case "reload":
		return Reload()
	case "clear":
		return ClearTable()
	case "qr":
		return ImportURL()
	case "uninstall":
		return Uninstall()
	case "-h", "--help", "help":
		Usage()
		return nil
	default:
		return fmt.Errorf("未知命令：%s", args[0])
	}
}

func Usage() {
	fmt.Print(`KnockGate Go 服务端

用法：
  knockgate                 root 下打开交互菜单
  knockgate install         安装 / 修复
  knockgate reset           重置保护端口、敲门序列、密钥和时间
  knockgate update          按当前配置重写规则并重启服务
  knockgate serve           systemd 使用的 pcap 抓包服务模式
  knockgate status          查看服务、规则、白名单和配置
  knockgate logs            查看最近日志
  knockgate logs-follow     跟随日志
  knockgate allow IPv4      手动临时放行 IP
  knockgate flush           清空临时白名单
  knockgate clear           删除 KnockGate 自己的 nft table
  knockgate qr              输出客户端导入 URL / QR
  knockgate uninstall       卸载
`)
}

func Serve() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	return knock.ServePCAP(ctx, cfg)
}

func Install() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	if err := os.MkdirAll(config.Dir, 0700); err != nil {
		return err
	}
	if err := system.InstallPackages(); err != nil {
		return err
	}
	cfg, err := PromptConfig(config.LoadOrDefault())
	if err != nil {
		return err
	}
	if err := config.Save(cfg); err != nil {
		return err
	}
	if err := nft.Apply(cfg); err != nil {
		return err
	}
	if err := system.InstallSelf(); err != nil {
		return err
	}
	if err := system.WriteService(); err != nil {
		return err
	}
	if err := system.WriteReadme(); err != nil {
		return err
	}
	system.CleanupLegacy()
	if err := system.Systemctl("daemon-reload"); err != nil {
		return err
	}
	_ = system.Systemctl("enable", "knockgate.service")
	if err := system.Systemctl("restart", "knockgate.service"); err != nil {
		return err
	}
	fmt.Println(ui.Green("安装完成。SSH 和原防火墙规则未修改。"))
	PrintSummary(cfg)
	return ImportURL()
}

func Update() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	if err := nft.Apply(cfg); err != nil {
		return err
	}
	if err := system.WriteService(); err != nil {
		return err
	}
	if err := system.Systemctl("daemon-reload"); err != nil {
		return err
	}
	return system.Systemctl("restart", "knockgate.service")
}

func Reset() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	cfg, err := PromptConfig(config.LoadOrDefault())
	if err != nil {
		return err
	}
	if err := config.Save(cfg); err != nil {
		return err
	}
	return Update()
}

func Status() error {
	cfg := config.LoadOrDefault()
	PrintSummary(cfg)
	fmt.Println()
	_ = system.Stream("systemctl", "status", "knockgate.service", "--no-pager")
	fmt.Println()
	_ = nft.ShowTable()
	fmt.Println()
	_ = nft.ShowAllowlist()
	return nil
}

func Logs(follow bool) error {
	args := []string{"-u", "knockgate.service"}
	if follow {
		args = append(args, "-f")
	} else {
		args = append(args, "-n", "100", "--no-pager")
	}
	return system.Stream("journalctl", args...)
}

func Allowlist() error {
	cfg := config.LoadOrDefault()
	fmt.Printf("保护端口：%s\n", config.JoinPorts(cfg.ProtectedPorts))
	return nft.ShowAllowlist()
}

func AddAllow(ip string) error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	addr, err := netip.ParseAddr(ip)
	if err != nil || !addr.Is4() {
		return fmt.Errorf("无效 IPv4：%s", ip)
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	return nft.AddAllow(ip, cfg.OpenTimeout)
}

func FlushAllowlist() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	if err := nft.FlushAllowlist(); err != nil {
		return err
	}
	fmt.Println(ui.Green("临时白名单已清空。"))
	return nil
}

func Reload() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	return nft.Apply(cfg)
}

func ClearTable() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	if !ui.Confirm("删除 KnockGate 自己的 nft table？不会修改 SSH 或其他防火墙规则", false) {
		return errors.New("已取消")
	}
	return nft.ClearTable()
}

func Uninstall() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	if !ui.Confirm("卸载 KnockGate Go 服务并删除它自己的 nft table？", false) {
		return errors.New("已取消")
	}
	_ = system.Systemctl("disable", "--now", "knockgate.service")
	_ = nft.ClearTable()
	_ = os.Remove(system.ServiceFile)
	system.CleanupLegacy()
	_ = system.Systemctl("daemon-reload")
	if ui.Confirm("删除 /usr/local/bin/knockgate？", false) {
		_ = os.Remove(system.InstallPath)
	}
	if ui.Confirm("删除 /etc/knockgate？", false) {
		_ = os.RemoveAll(config.Dir)
	}
	fmt.Println(ui.Green("卸载完成。"))
	return nil
}

func Menu() error {
	for {
		fmt.Println()
		fmt.Println(ui.Cyan("KnockGate Manager"))
		fmt.Println("1. 安装 / 修复")
		fmt.Println("2. 更新配置")
		fmt.Println("3. 重置保护端口、敲门序列、密钥和时间")
		fmt.Println("4. 查看状态")
		fmt.Println("5. 查看日志")
		fmt.Println("6. 查看临时白名单")
		fmt.Println("7. 添加 IP 到临时白名单")
		fmt.Println("8. 清空临时白名单")
		fmt.Println("9. 重载 KnockGate 规则")
		fmt.Println("10. 清空 KnockGate 防火墙表")
		fmt.Println("11. 生成客户端导入二维码")
		fmt.Println("12. 卸载")
		fmt.Println("13. 退出")
		switch ui.Prompt("请选择", "") {
		case "1":
			_ = Install()
		case "2":
			_ = Update()
		case "3":
			_ = Reset()
		case "4":
			_ = Status()
		case "5":
			_ = Logs(false)
		case "6":
			_ = Allowlist()
		case "7":
			_ = AddAllow(ui.Prompt("IPv4", ""))
		case "8":
			_ = FlushAllowlist()
		case "9":
			_ = Reload()
		case "10":
			_ = ClearTable()
		case "11":
			_ = ImportURL()
		case "12":
			_ = Uninstall()
		case "13", "q", "quit", "exit":
			return nil
		default:
			fmt.Println(ui.Yellow("未知选择。"))
		}
	}
}

func PromptConfig(current config.Config) (config.Config, error) {
	fmt.Println(ui.Red("警告：Go 版 KnockGate 使用 libpcap 抓包，不监听敲门端口。"))
	fmt.Println(ui.Yellow("它只管理 table inet knockgate，只 drop 你输入的保护 TCP 端口。SSH 端口规则不读取、不询问、不修改。"))
	fmt.Println(ui.Yellow("云防火墙必须允许 UDP 敲门包到达主机；主机 nftables 不需要开放敲门端口。"))
	fmt.Println()

	protected := promptPorts("保护 TCP 端口", current.ProtectedPorts, false)
	avoid := append([]int{}, protected...)
	avoid = append(avoid, detectListeningPorts()...)
	knocks := rollKnockPorts(avoid, config.DefaultKnockCount)
	fmt.Printf("随机生成敲门端口：%s\n", config.JoinPorts(knocks))
	knocks = promptPorts("UDP 敲门序列", knocks, true)
	openTimeout := ui.Prompt("开门时长", valueString(current.OpenTimeout, config.DefaultOpenTimeout))
	for !config.ValidTimeout(openTimeout) {
		fmt.Println(ui.Yellow("格式示例：30s、10m、12h、1d"))
		openTimeout = ui.Prompt("开门时长", config.DefaultOpenTimeout)
	}
	seqTimeout := promptInt("序列超时秒数", valueInt(current.SeqTimeoutSeconds, config.DefaultSeqTimeout))
	hmacWindow := promptInt("timestamp/HMAC 容忍窗口秒数", valueInt(current.HMACWindowSeconds, config.DefaultHMACWindow))
	iface := ui.Prompt("pcap 抓包网卡", valueString(current.Interface, detectDefaultInterface()))
	secret := current.Secret
	if secret == "" || ui.Confirm("重新生成 HMAC 密钥？", secret == "") {
		generated, err := config.GenerateSecret()
		if err != nil {
			return config.Config{}, err
		}
		secret = generated
	}

	next := config.Config{
		ProtectedPorts:    protected,
		KnockPorts:        knocks,
		OpenTimeout:       openTimeout,
		SeqTimeoutSeconds: seqTimeout,
		HMACWindowSeconds: hmacWindow,
		Secret:            secret,
		Interface:         iface,
		Mode:              config.DefaultMode,
	}
	PrintSummary(next)
	if !ui.ConfirmYES("应用配置？") {
		return config.Config{}, errors.New("已取消")
	}
	return next, nil
}

func PrintSummary(cfg config.Config) {
	fmt.Println()
	fmt.Println(ui.Cyan("配置摘要"))
	fmt.Println("模式：Go + libpcap HMAC UDP 敲门 + nftables 保护端口叠加")
	fmt.Printf("保护 TCP 端口：%s\n", config.JoinPorts(cfg.ProtectedPorts))
	fmt.Printf("UDP 敲门序列：%s\n", strings.ReplaceAll(config.JoinPorts(cfg.KnockPorts), ",", " -> "))
	fmt.Printf("开门时长：%s\n", cfg.OpenTimeout)
	fmt.Printf("序列超时：%ds\n", cfg.SeqTimeoutSeconds)
	fmt.Printf("timestamp/HMAC 窗口：%ds\n", cfg.HMACWindowSeconds)
	fmt.Printf("pcap 网卡：%s\n", cfg.Interface)
}

func ImportURL() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	host := detectHost()
	url := fmt.Sprintf("knockgate://import/v1?scheme=udp-hmac&host=%s&knock_ports=%s&protected_ports=%s&seq_timeout=%d&open_timeout=%s&hmac_window=%d&secret=%s&label=KnockGate",
		escape(host), escape(config.JoinPorts(cfg.KnockPorts)), escape(config.JoinPorts(cfg.ProtectedPorts)), cfg.SeqTimeoutSeconds, escape(cfg.OpenTimeout), cfg.HMACWindowSeconds, escape(cfg.Secret))
	fmt.Println(ui.Cyan("客户端导入 URL："))
	fmt.Println(url)
	if _, err := exec.LookPath("qrencode"); err == nil {
		fmt.Println()
		_ = system.Stream("qrencode", "-t", "ANSIUTF8", url)
	}
	return nil
}

func promptPorts(label string, def []int, sequence bool) []int {
	for {
		text := ui.Prompt(label, config.JoinPorts(def))
		ports, err := config.ParsePorts(text, sequence)
		if err == nil {
			return ports
		}
		fmt.Println(ui.Yellow(err.Error()))
	}
}

func promptInt(label string, def int) int {
	for {
		text := ui.Prompt(label, strconv.Itoa(def))
		value, err := strconv.Atoi(text)
		if err == nil && value > 0 {
			return value
		}
		fmt.Println(ui.Yellow("请输入正整数。"))
	}
}

func rollKnockPorts(avoid []int, count int) []int {
	avoidSet := map[int]bool{}
	for _, port := range avoid {
		avoidSet[port] = true
	}
	var out []int
	for len(out) < count {
		port := randomPort()
		if avoidSet[port] || contains(out, port) {
			continue
		}
		out = append(out, port)
	}
	return out
}

func randomPort() int {
	var b [2]byte
	if _, err := rand.Read(b[:]); err != nil {
		return 20000
	}
	return 20000 + int(binary.BigEndian.Uint16(b[:])%45536)
}

func detectListeningPorts() []int {
	out, err := exec.Command("ss", "-H", "-ltun").Output()
	if err != nil {
		return nil
	}
	found := map[int]bool{}
	re := regexp.MustCompile(`:([0-9]{1,5})\s`)
	for _, match := range re.FindAllStringSubmatch(string(out)+" ", -1) {
		port, _ := strconv.Atoi(match[1])
		if config.ValidPort(port) {
			found[port] = true
		}
	}
	var ports []int
	for port := range found {
		ports = append(ports, port)
	}
	sort.Ints(ports)
	return ports
}

func detectDefaultInterface() string {
	if iface, err := knock.DefaultInterface(); err == nil {
		return iface
	}
	return "eth0"
}

func detectHost() string {
	out, err := exec.Command("sh", "-c", `ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'`).Output()
	if err == nil && strings.TrimSpace(string(out)) != "" {
		return strings.TrimSpace(string(out))
	}
	ifaces, _ := net.Interfaces()
	for _, iface := range ifaces {
		addrs, _ := iface.Addrs()
		for _, addr := range addrs {
			ip, _, _ := net.ParseCIDR(addr.String())
			if ip != nil && ip.To4() != nil && !ip.IsLoopback() {
				return ip.String()
			}
		}
	}
	return "SERVER_IP"
}

func valueString(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func valueInt(value, fallback int) int {
	if value <= 0 {
		return fallback
	}
	return value
}

func contains(values []int, needle int) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}
	return false
}

func escape(value string) string {
	replacer := strings.NewReplacer(" ", "%20", ",", "%2C", ":", "%3A", "/", "%2F", "+", "%2B", "=", "%3D")
	return replacer.Replace(value)
}
