package knock

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"os/exec"
	"strings"
	"time"

	"github.com/google/gopacket"
	"github.com/google/gopacket/layers"
	"github.com/google/gopacket/pcap"
	"github.com/leconio/knockport/internal/config"
	"github.com/leconio/knockport/internal/nft"
)

// ServePCAP 使用 libpcap 抓取 UDP 敲门包。
//
// 注意：这里不会监听 UDP socket，也不会让敲门端口变成 open。
// 数据包在进入 nftables input chain 前已经能被 pcap 看到，所以端口即使被 drop，
// 仍然可以完成 HMAC 敲门校验。
func ServePCAP(ctx context.Context, cfg config.Config) error {
	secret, err := config.DecodeSecret(cfg.Secret)
	if err != nil {
		return err
	}
	if cfg.Interface == "" {
		iface, err := DefaultInterface()
		if err != nil {
			return err
		}
		cfg.Interface = iface
	}
	if err := nft.Apply(cfg); err != nil {
		return err
	}

	handle, err := pcap.OpenLive(cfg.Interface, 65535, true, time.Second)
	if err != nil {
		return fmt.Errorf("打开 pcap 网卡 %s 失败：%w", cfg.Interface, err)
	}
	defer handle.Close()

	filter := bpfFilter(cfg.KnockPorts)
	if err := handle.SetBPFFilter(filter); err != nil {
		return fmt.Errorf("设置 BPF 过滤器失败：%w", err)
	}
	log.Printf("pcap 抓包已启动：interface=%s filter=%q protected=%s", cfg.Interface, filter, config.JoinProtectedPorts(cfg.ProtectedPorts))

	go func() {
		<-ctx.Done()
		handle.Close()
	}()

	source := gopacket.NewPacketSource(handle, handle.LinkType())
	state := NewState()
	for {
		if ctx.Err() != nil {
			return nil
		}
		packet, err := source.NextPacket()
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, pcap.NextErrorTimeoutExpired) {
				continue
			}
			if strings.Contains(err.Error(), "handle is closed") {
				return nil
			}
			log.Printf("读取 pcap 包失败：%v", err)
			continue
		}
		processPacket(cfg, secret, state, packet)
	}
}

func processPacket(cfg config.Config, secret []byte, state *State, packet gopacket.Packet) {
	ip4Layer := packet.Layer(layers.LayerTypeIPv4)
	udpLayer := packet.Layer(layers.LayerTypeUDP)
	if ip4Layer == nil || udpLayer == nil {
		return
	}
	ip4 := ip4Layer.(*layers.IPv4)
	udp := udpLayer.(*layers.UDP)
	src := ip4.SrcIP.To4()
	if src == nil {
		return
	}
	destPort := int(udp.DstPort)
	if state.Accept(cfg, secret, src.String(), destPort, udp.Payload, time.Now()) {
		if err := nft.AddAllow(src.String(), cfg.OpenTimeout); err != nil {
			log.Printf("写入 nft 临时白名单失败：source=%s err=%v", src.String(), err)
			return
		}
		log.Printf("已临时放行：source=%s timeout=%s", src.String(), cfg.OpenTimeout)
	}
}

func bpfFilter(ports []int) string {
	var parts []string
	for _, port := range ports {
		parts = append(parts, fmt.Sprintf("udp dst port %d", port))
	}
	return "ip and (" + strings.Join(parts, " or ") + ")"
}

func DefaultInterface() (string, error) {
	out, err := exec.Command("sh", "-c", `ip -4 route show default 0.0.0.0/0 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'`).Output()
	if err == nil {
		if iface := strings.TrimSpace(string(out)); iface != "" {
			return iface, nil
		}
	}
	ifaces, err := net.Interfaces()
	if err != nil {
		return "", err
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagLoopback == 0 && iface.Flags&net.FlagUp != 0 {
			return iface.Name, nil
		}
	}
	return "", fmt.Errorf("无法检测默认网卡，请在配置中设置 INTERFACE")
}
