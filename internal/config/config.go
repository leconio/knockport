package config

import (
	"bufio"
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const (
	Dir          = "/etc/knockgate"
	File         = "/etc/knockgate/knockgate.conf"
	NFTFile      = "/etc/knockgate/knockgate.nft"
	NFTApplyFile = "/etc/knockgate/knockgate.apply.nft"
	ReadmeFile   = "/etc/knockgate/README"
	DefaultMode  = "go_hmac_pcap_overlay"
)

const (
	DefaultProtectedPorts = "5432"
	DefaultOpenTimeout    = "12h"
	DefaultSeqTimeout     = 10
	DefaultHMACWindow     = 60
	DefaultKnockCount     = 6
	DefaultProtectHook    = HookPrerouting
)

// Config 是服务端唯一配置来源。Go 版不再保存 SSH 端口，因为 KnockGate 不接管 SSH。
type Config struct {
	ProtectedPorts    []ProtectedPort
	KnockPorts        []int
	OpenTimeout       string
	SeqTimeoutSeconds int
	HMACWindowSeconds int
	Secret            string
	Interface         string
	ProtectHook       ProtectHook
	Mode              string
}

type ProtectHook string

const (
	HookInput      ProtectHook = "input"
	HookPrerouting ProtectHook = "prerouting"
)

type Proto string

const (
	ProtoBoth Proto = "both"
	ProtoTCP  Proto = "tcp"
	ProtoUDP  Proto = "udp"
)

type ProtectedPort struct {
	Port  int
	Proto Proto
}

// Load 读取 /etc/knockgate/knockgate.conf，并兼容旧 shell 版的 KEY=VALUE 格式。
func Load() (Config, error) {
	values, err := ParseFile(File)
	if err != nil {
		return Config{}, err
	}
	protected, err := ParseProtectedPorts(first(values["PROTECTED_PORTS"], values["PROTECTED_PORT"], DefaultProtectedPorts))
	if err != nil {
		return Config{}, err
	}
	knocks, err := ParsePorts(values["KNOCK_PORTS"], true)
	if err != nil {
		return Config{}, err
	}
	cfg := Config{
		ProtectedPorts:    protected,
		KnockPorts:        knocks,
		OpenTimeout:       first(values["OPEN_TIMEOUT"], DefaultOpenTimeout),
		SeqTimeoutSeconds: intValue(values["SEQ_TIMEOUT"], DefaultSeqTimeout),
		HMACWindowSeconds: intValue(values["HMAC_WINDOW"], DefaultHMACWindow),
		Secret:            values["SECRET"],
		Interface:         values["INTERFACE"],
		ProtectHook:       ProtectHook(first(values["PROTECT_HOOK"], values["HOOK"], string(DefaultProtectHook))),
		Mode:              first(values["MODE"], DefaultMode),
	}
	if cfg.Secret == "" {
		return Config{}, errors.New("配置缺少 SECRET，请执行 install/reset 重新生成 HMAC 密钥")
	}
	if err := Validate(cfg); err != nil {
		return Config{}, err
	}
	return cfg, nil
}

// LoadOrDefault 用于首次安装交互；没有配置时生成一个新密钥。
func LoadOrDefault() Config {
	cfg, err := Load()
	if err == nil {
		return cfg
	}
	secret, _ := GenerateSecret()
	return Config{
		ProtectedPorts:    []ProtectedPort{{Port: 5432, Proto: ProtoBoth}},
		OpenTimeout:       DefaultOpenTimeout,
		SeqTimeoutSeconds: DefaultSeqTimeout,
		HMACWindowSeconds: DefaultHMACWindow,
		Secret:            secret,
		ProtectHook:       DefaultProtectHook,
		Mode:              DefaultMode,
	}
}

// Save 写入 root-only 配置文件。SECRET 会进入二维码，必须按敏感信息处理。
func Save(cfg Config) error {
	if err := Validate(cfg); err != nil {
		return err
	}
	if err := os.MkdirAll(Dir, 0700); err != nil {
		return err
	}
	data := fmt.Sprintf(`PROTECTED_PORTS=%s
KNOCK_PORTS=%s
OPEN_TIMEOUT=%s
SEQ_TIMEOUT=%d
HMAC_WINDOW=%d
SECRET=%s
INTERFACE=%s
PROTECT_HOOK=%s
MODE=%s
`, quote(JoinProtectedPorts(cfg.ProtectedPorts)), quote(JoinPorts(cfg.KnockPorts)), quote(cfg.OpenTimeout), cfg.SeqTimeoutSeconds, cfg.HMACWindowSeconds, quote(cfg.Secret), quote(cfg.Interface), quote(string(cfg.ProtectHook)), quote(DefaultMode))
	return os.WriteFile(File, []byte(data), 0600)
}

func ParseFile(path string) (map[string]string, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	values := map[string]string{}
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		values[strings.TrimSpace(key)] = parseValue(strings.TrimSpace(value))
	}
	return values, scanner.Err()
}

func parseValue(value string) string {
	if len(value) >= 2 && value[0] == '"' {
		if parsed, err := strconv.Unquote(value); err == nil {
			return parsed
		}
	}
	return strings.Trim(value, `"`)
}

func quote(value string) string {
	return strconv.Quote(value)
}

func ParsePorts(text string, sequence bool) ([]int, error) {
	if strings.TrimSpace(text) == "" {
		return nil, errors.New("端口列表为空")
	}
	var ports []int
	seen := map[int]bool{}
	for _, part := range regexp.MustCompile(`[,\s]+`).Split(strings.TrimSpace(text), -1) {
		if part == "" {
			continue
		}
		port, err := strconv.Atoi(part)
		if err != nil || !ValidPort(port) {
			return nil, fmt.Errorf("无效端口：%s", part)
		}
		if seen[port] {
			if sequence {
				return nil, fmt.Errorf("敲门序列端口不能重复：%d", port)
			}
			continue
		}
		seen[port] = true
		ports = append(ports, port)
	}
	if len(ports) == 0 {
		return nil, errors.New("端口列表为空")
	}
	return ports, nil
}

func ParseProtectedPorts(text string) ([]ProtectedPort, error) {
	if strings.TrimSpace(text) == "" {
		return nil, errors.New("保护端口列表为空")
	}
	seen := map[string]bool{}
	var ports []ProtectedPort
	for _, part := range regexp.MustCompile(`[,\s]+`).Split(strings.TrimSpace(text), -1) {
		if part == "" {
			continue
		}
		portPart := part
		proto := ProtoBoth
		if strings.Contains(part, "/") {
			left, right, ok := strings.Cut(part, "/")
			if !ok || left == "" || right == "" {
				return nil, fmt.Errorf("无效保护端口：%s", part)
			}
			portPart = left
			switch strings.ToLower(right) {
			case "tcp":
				proto = ProtoTCP
			case "udp":
				proto = ProtoUDP
			default:
				return nil, fmt.Errorf("无效协议：%s，只支持 tcp/udp", right)
			}
		}
		port, err := strconv.Atoi(portPart)
		if err != nil || !ValidPort(port) {
			return nil, fmt.Errorf("无效端口：%s", portPart)
		}
		key := fmt.Sprintf("%d/%s", port, proto)
		if seen[key] {
			continue
		}
		seen[key] = true
		ports = append(ports, ProtectedPort{Port: port, Proto: proto})
	}
	if len(ports) == 0 {
		return nil, errors.New("保护端口列表为空")
	}
	return ports, nil
}

func JoinPorts(ports []int) string {
	parts := make([]string, len(ports))
	for i, port := range ports {
		parts[i] = strconv.Itoa(port)
	}
	return strings.Join(parts, ",")
}

func JoinProtectedPorts(ports []ProtectedPort) string {
	parts := make([]string, len(ports))
	for i, item := range ports {
		switch item.Proto {
		case ProtoTCP:
			parts[i] = fmt.Sprintf("%d/tcp", item.Port)
		case ProtoUDP:
			parts[i] = fmt.Sprintf("%d/udp", item.Port)
		default:
			parts[i] = strconv.Itoa(item.Port)
		}
	}
	return strings.Join(parts, ",")
}

func ProtectedTCPPorts(ports []ProtectedPort) []int {
	return protectedPortsFor(ports, ProtoTCP)
}

func ProtectedUDPPorts(ports []ProtectedPort) []int {
	return protectedPortsFor(ports, ProtoUDP)
}

func ProtectedPortNumbers(ports []ProtectedPort) []int {
	seen := map[int]bool{}
	var out []int
	for _, item := range ports {
		if !seen[item.Port] {
			seen[item.Port] = true
			out = append(out, item.Port)
		}
	}
	sort.Ints(out)
	return out
}

func protectedPortsFor(ports []ProtectedPort, proto Proto) []int {
	seen := map[int]bool{}
	var out []int
	for _, item := range ports {
		if item.Proto == ProtoBoth || item.Proto == proto {
			if !seen[item.Port] {
				seen[item.Port] = true
				out = append(out, item.Port)
			}
		}
	}
	sort.Ints(out)
	return out
}

func ValidPort(port int) bool {
	return port >= 1 && port <= 65535
}

func ValidTimeout(value string) bool {
	return regexp.MustCompile(`^[0-9]+(ms|s|m|h|d|w)?$`).MatchString(value)
}

func ValidInterface(value string) bool {
	if value == "" {
		return true
	}
	return regexp.MustCompile(`^[A-Za-z0-9_.:@-]{1,64}$`).MatchString(value)
}

func ValidProtectHook(value ProtectHook) bool {
	return value == HookInput || value == HookPrerouting
}

func Validate(cfg Config) error {
	if len(cfg.ProtectedPorts) == 0 {
		return errors.New("保护端口列表为空")
	}
	if len(cfg.KnockPorts) == 0 {
		return errors.New("敲门端口列表为空")
	}
	if !ValidTimeout(cfg.OpenTimeout) {
		return fmt.Errorf("OPEN_TIMEOUT 格式无效：%s", cfg.OpenTimeout)
	}
	if cfg.SeqTimeoutSeconds <= 0 {
		return errors.New("SEQ_TIMEOUT 必须是正整数")
	}
	if cfg.HMACWindowSeconds <= 0 {
		return errors.New("HMAC_WINDOW 必须是正整数")
	}
	if _, err := DecodeSecret(cfg.Secret); err != nil {
		return err
	}
	if !ValidInterface(cfg.Interface) {
		return fmt.Errorf("INTERFACE 格式无效：%s", cfg.Interface)
	}
	if !ValidProtectHook(cfg.ProtectHook) {
		return fmt.Errorf("PROTECT_HOOK 格式无效：%s，只支持 input/prerouting", cfg.ProtectHook)
	}
	return nil
}

func GenerateSecret() (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func DecodeSecret(value string) ([]byte, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(value)
	if err != nil || len(decoded) < 32 {
		return nil, errors.New("SECRET 必须是至少 32 字节的 base64url 字符串")
	}
	return decoded, nil
}

func SortedUnique(ports []int) []int {
	seen := map[int]bool{}
	var out []int
	for _, port := range ports {
		if ValidPort(port) && !seen[port] {
			seen[port] = true
			out = append(out, port)
		}
	}
	sort.Ints(out)
	return out
}

func first(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func intValue(value string, fallback int) int {
	parsed, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
