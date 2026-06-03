package knock

import (
	"log"
	"sync"
	"time"

	"github.com/leconio/knockport/internal/config"
	"github.com/leconio/knockport/internal/protocol"
)

type sequenceState struct {
	next     int
	deadline time.Time
}

type State struct {
	mu     sync.Mutex
	seq    map[string]sequenceState
	nonces map[string]time.Time
}

func NewState() *State {
	return &State{
		seq:    map[string]sequenceState{},
		nonces: map[string]time.Time{},
	}
}

// Accept 验证端口顺序，并且只在最后一步校验 HMAC、timestamp、nonce。
//
// 顺序语义：
// - 第 0 步必须先到；
// - 整个序列必须在 SEQ_TIMEOUT 内完成；
// - 前面的步骤只检查目的端口顺序，不解析 payload，降低 CPU 压力；
// - 只有最后一个端口的 payload 必须通过 HMAC/timestamp/nonce 校验；
// - 最后一步 nonce 在窗口内只能使用一次，避免录包重放。
func (s *State) Accept(cfg config.Config, secret []byte, sourceIP string, destPort int, payload []byte, now time.Time) bool {
	if len(cfg.KnockPorts) == 0 {
		return false
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.cleanup(now)

	current, exists := s.seq[sourceIP]
	if !exists || now.After(current.deadline) {
		if destPort != cfg.KnockPorts[0] {
			delete(s.seq, sourceIP)
			return false
		}
		return s.startOrVerifyFinal(cfg, secret, sourceIP, destPort, payload, now)
	}

	if current.next >= len(cfg.KnockPorts) || destPort != cfg.KnockPorts[current.next] {
		if destPort == cfg.KnockPorts[0] {
			return s.startOrVerifyFinal(cfg, secret, sourceIP, destPort, payload, now)
		}
		delete(s.seq, sourceIP)
		return false
	}

	if current.next == len(cfg.KnockPorts)-1 {
		return s.verifyFinal(cfg, secret, sourceIP, destPort, payload, now)
	}

	current.next++
	s.seq[sourceIP] = current
	return false
}

func (s *State) startOrVerifyFinal(cfg config.Config, secret []byte, sourceIP string, destPort int, payload []byte, now time.Time) bool {
	if len(cfg.KnockPorts) == 1 {
		return s.verifyFinal(cfg, secret, sourceIP, destPort, payload, now)
	}
	s.seq[sourceIP] = sequenceState{
		next:     1,
		deadline: now.Add(time.Duration(cfg.SeqTimeoutSeconds) * time.Second),
	}
	log.Printf("敲门序列开始：source=%s", sourceIP)
	return false
}

func (s *State) verifyFinal(cfg config.Config, secret []byte, sourceIP string, destPort int, payload []byte, now time.Time) bool {
	delete(s.seq, sourceIP)
	parsed, ok := protocol.Verify(secret, destPort, string(payload), cfg.HMACWindowSeconds, now)
	if !ok || parsed.Step != len(cfg.KnockPorts)-1 {
		log.Printf("最终敲门包 HMAC 校验失败：source=%s port=%d", sourceIP, destPort)
		return false
	}
	nonceKey := sourceIP + "|" + parsed.Nonce
	if _, exists := s.nonces[nonceKey]; exists {
		log.Printf("拒绝重放 nonce：source=%s step=%d port=%d", sourceIP, parsed.Step, destPort)
		return false
	}
	s.nonces[nonceKey] = now.Add(time.Duration(cfg.HMACWindowSeconds+cfg.SeqTimeoutSeconds) * time.Second)
	log.Printf("敲门序列完成：source=%s", sourceIP)
	return true
}

func (s *State) cleanup(now time.Time) {
	for key, state := range s.seq {
		if now.After(state.deadline) {
			delete(s.seq, key)
		}
	}
	for key, expires := range s.nonces {
		if now.After(expires) {
			delete(s.nonces, key)
		}
	}
}
