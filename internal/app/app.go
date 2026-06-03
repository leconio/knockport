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
		ui.SetLanguageFromEnvDefault()
		Usage()
		return nil
	}
	if args[0] == "install" || args[0] == "repair" || args[0] == "reset" {
		ui.ChooseLanguage()
	} else {
		ui.SetLanguageFromEnvDefault()
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
			return errors.New(ui.T("用法：knockgate allow IPv4", "usage: knockgate allow IPv4"))
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
		return fmt.Errorf("%s: %s", ui.T("未知命令", "unknown command"), args[0])
	}
}

func Usage() {
	fmt.Print(ui.T(`KnockGate Go 服务端

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
`, `KnockGate Go server

Usage:
  knockgate                 Open interactive menu as root
  knockgate install         Install / repair
  knockgate reset           Reset protected ports, knock sequence, secret, and timings
  knockgate update          Rewrite rules and restart service from current config
  knockgate serve           pcap capture service mode for systemd
  knockgate status          Show service, rules, allowlist, and config
  knockgate logs            Show recent logs
  knockgate logs-follow     Follow logs
  knockgate allow IPv4      Manually add IP to temporary allowlist
  knockgate flush           Flush temporary allowlist
  knockgate clear           Delete KnockGate's own nft table
  knockgate qr              Print client import URL / QR
  knockgate uninstall       Uninstall
`))
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
	fmt.Println(ui.Green(ui.T("安装完成。SSH 和原防火墙规则未修改。", "Installed. SSH and existing firewall rules were not modified.")))
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
	fmt.Printf("%s: %s\n", ui.T("保护端口", "Protected ports"), config.JoinPorts(cfg.ProtectedPorts))
	return nft.ShowAllowlist()
}

func AddAllow(ip string) error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	addr, err := netip.ParseAddr(ip)
	if err != nil || !addr.Is4() {
		return fmt.Errorf("%s: %s", ui.T("无效 IPv4", "invalid IPv4"), ip)
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
	fmt.Println(ui.Green(ui.T("临时白名单已清空。", "Temporary allowlist flushed.")))
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
	if !ui.Confirm(ui.T("删除 KnockGate 自己的 nft table？不会修改 SSH 或其他防火墙规则", "Delete KnockGate's own nft table? SSH and other firewall rules are not modified"), false) {
		return errors.New(ui.T("已取消", "cancelled"))
	}
	return nft.ClearTable()
}

func Uninstall() error {
	if err := system.RequireRoot(); err != nil {
		return err
	}
	if !ui.Confirm(ui.T("卸载 KnockGate Go 服务并删除它自己的 nft table？", "Uninstall KnockGate Go service and delete its own nft table?"), false) {
		return errors.New(ui.T("已取消", "cancelled"))
	}
	_ = system.Systemctl("disable", "--now", "knockgate.service")
	_ = nft.ClearTable()
	_ = os.Remove(system.ServiceFile)
	system.CleanupLegacy()
	_ = system.Systemctl("daemon-reload")
	if ui.Confirm(ui.T("删除 /usr/local/bin/knockgate？", "Delete /usr/local/bin/knockgate?"), false) {
		_ = os.Remove(system.InstallPath)
	}
	if ui.Confirm(ui.T("删除 /etc/knockgate？", "Delete /etc/knockgate?"), false) {
		_ = os.RemoveAll(config.Dir)
	}
	fmt.Println(ui.Green(ui.T("卸载完成。", "Uninstall finished.")))
	return nil
}

func Menu() error {
	ui.ChooseLanguage()
	for {
		fmt.Println()
		fmt.Println(ui.Cyan("KnockGate Manager"))
		fmt.Println(ui.T("1. 安装 / 修复", "1. Install / Repair"))
		fmt.Println(ui.T("2. 更新配置", "2. Update config"))
		fmt.Println(ui.T("3. 重置保护端口、敲门序列、密钥和时间", "3. Reset protected ports, knock sequence, secret, and timings"))
		fmt.Println(ui.T("4. 查看状态", "4. Show status"))
		fmt.Println(ui.T("5. 查看日志", "5. Show logs"))
		fmt.Println(ui.T("6. 查看临时白名单", "6. Show temporary allowlist"))
		fmt.Println(ui.T("7. 添加 IP 到临时白名单", "7. Add IP to temporary allowlist"))
		fmt.Println(ui.T("8. 清空临时白名单", "8. Flush temporary allowlist"))
		fmt.Println(ui.T("9. 重载 KnockGate 规则", "9. Reload KnockGate rules"))
		fmt.Println(ui.T("10. 清空 KnockGate 防火墙表", "10. Clear KnockGate firewall table"))
		fmt.Println(ui.T("11. 生成客户端导入二维码", "11. Generate client import QR"))
		fmt.Println(ui.T("12. 卸载", "12. Uninstall"))
		fmt.Println(ui.T("13. 退出", "13. Exit"))
		switch ui.Prompt(ui.T("请选择", "Select"), "") {
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
			fmt.Println(ui.Yellow(ui.T("未知选择。", "Unknown selection.")))
		}
	}
}

func PromptConfig(current config.Config) (config.Config, error) {
	fmt.Println(ui.Red(ui.T("警告：Go 版 KnockGate 使用 libpcap 抓包，不监听敲门端口。", "WARNING: KnockGate Go uses libpcap capture and does not listen on knock ports.")))
	fmt.Println(ui.Yellow(ui.T("它只管理 table inet knockgate，只 drop 你输入的保护 TCP 端口。SSH 端口规则不读取、不询问、不修改。", "It only manages table inet knockgate and only drops the protected TCP ports you enter. SSH rules are not read, prompted for, or modified.")))
	fmt.Println(ui.Yellow(ui.T("云防火墙必须允许 UDP 敲门包到达主机；主机 nftables 不需要开放敲门端口。", "Cloud firewalls must allow UDP knock packets to reach the host; host nftables does not need to open knock ports.")))
	fmt.Println()

	protected := promptPorts(ui.T("保护 TCP 端口", "Protected TCP ports"), current.ProtectedPorts, false)
	avoid := append([]int{}, protected...)
	avoid = append(avoid, detectListeningPorts()...)
	knocks := rollKnockPorts(avoid, config.DefaultKnockCount)
	fmt.Printf("%s: %s\n", ui.T("随机生成敲门端口", "Rolled knock ports"), config.JoinPorts(knocks))
	knocks = promptPorts(ui.T("UDP 敲门序列", "UDP knock sequence"), knocks, true)
	openTimeout := ui.Prompt(ui.T("开门时长", "Open timeout"), valueString(current.OpenTimeout, config.DefaultOpenTimeout))
	for !config.ValidTimeout(openTimeout) {
		fmt.Println(ui.Yellow(ui.T("格式示例：30s、10m、12h、1d", "Examples: 30s, 10m, 12h, 1d")))
		openTimeout = ui.Prompt(ui.T("开门时长", "Open timeout"), config.DefaultOpenTimeout)
	}
	seqTimeout := promptInt(ui.T("序列超时秒数", "Sequence timeout seconds"), valueInt(current.SeqTimeoutSeconds, config.DefaultSeqTimeout))
	hmacWindow := promptInt(ui.T("timestamp/HMAC 容忍窗口秒数", "Timestamp/HMAC tolerance window seconds"), valueInt(current.HMACWindowSeconds, config.DefaultHMACWindow))
	iface := ui.Prompt(ui.T("pcap 抓包网卡", "pcap capture interface"), valueString(current.Interface, detectDefaultInterface()))
	secret := current.Secret
	if secret == "" || ui.Confirm(ui.T("重新生成 HMAC 密钥？", "Generate a new HMAC secret?"), secret == "") {
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
	if !ui.ConfirmYES(ui.T("应用配置？", "Apply configuration?")) {
		return config.Config{}, errors.New(ui.T("已取消", "cancelled"))
	}
	return next, nil
}

func PrintSummary(cfg config.Config) {
	fmt.Println()
	fmt.Println(ui.Cyan(ui.T("配置摘要", "Configuration summary")))
	fmt.Println(ui.T("模式：Go + libpcap UDP 顺序敲门 + 最后一步 HMAC + nftables 保护端口叠加", "Mode: Go + libpcap UDP sequence knock + final-step HMAC + nftables protective overlay"))
	fmt.Printf("%s: %s\n", ui.T("保护 TCP 端口", "Protected TCP ports"), config.JoinPorts(cfg.ProtectedPorts))
	fmt.Printf("%s: %s\n", ui.T("UDP 敲门序列", "UDP knock sequence"), strings.ReplaceAll(config.JoinPorts(cfg.KnockPorts), ",", " -> "))
	fmt.Printf("%s: %s\n", ui.T("开门时长", "Open timeout"), cfg.OpenTimeout)
	fmt.Printf("%s: %ds\n", ui.T("序列超时", "Sequence timeout"), cfg.SeqTimeoutSeconds)
	fmt.Printf("%s: %ds\n", ui.T("timestamp/HMAC 窗口", "Timestamp/HMAC window"), cfg.HMACWindowSeconds)
	fmt.Printf("%s: %s\n", ui.T("pcap 网卡", "pcap interface"), cfg.Interface)
}

func ImportURL() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	host := detectHost()
	url := fmt.Sprintf("knockgate://import/v1?scheme=udp-hmac&host=%s&knock_ports=%s&protected_ports=%s&seq_timeout=%d&open_timeout=%s&hmac_window=%d&secret=%s&label=KnockGate",
		escape(host), escape(config.JoinPorts(cfg.KnockPorts)), escape(config.JoinPorts(cfg.ProtectedPorts)), cfg.SeqTimeoutSeconds, escape(cfg.OpenTimeout), cfg.HMACWindowSeconds, escape(cfg.Secret))
	fmt.Println(ui.Cyan(ui.T("客户端导入 URL：", "Client import URL:")))
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
		fmt.Println(ui.Yellow(ui.T("请输入正整数。", "Please enter a positive integer.")))
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
