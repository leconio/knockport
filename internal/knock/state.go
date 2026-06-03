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

// Accept 验证 HMAC、timestamp、nonce 和端口顺序。
//
// 顺序语义：
// - 第 0 步必须先到；
// - 整个序列必须在 SEQ_TIMEOUT 内完成；
// - 合法 HMAC 但顺序错误会重置该来源 IP 的状态；
// - nonce 在窗口内只能使用一次，避免录包重放。
func (s *State) Accept(cfg config.Config, secret []byte, sourceIP string, destPort int, payload []byte, now time.Time) bool {
	parsed, ok := protocol.Verify(secret, destPort, string(payload), cfg.HMACWindowSeconds, now)
	if !ok {
		return false
	}
	if parsed.Step >= len(cfg.KnockPorts) || cfg.KnockPorts[parsed.Step] != destPort {
		return false
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.cleanup(now)

	nonceKey := sourceIP + "|" + parsed.Nonce
	if _, exists := s.nonces[nonceKey]; exists {
		log.Printf("拒绝重放 nonce：source=%s step=%d port=%d", sourceIP, parsed.Step, destPort)
		return false
	}
	s.nonces[nonceKey] = now.Add(time.Duration(cfg.HMACWindowSeconds+cfg.SeqTimeoutSeconds) * time.Second)

	current, exists := s.seq[sourceIP]
	if !exists || now.After(current.deadline) {
		if parsed.Step != 0 {
			delete(s.seq, sourceIP)
			return false
		}
		return s.startOrComplete(cfg, sourceIP, now)
	}

	if parsed.Step != current.next {
		if parsed.Step == 0 {
			return s.startOrComplete(cfg, sourceIP, now)
		}
		delete(s.seq, sourceIP)
		return false
	}

	if parsed.Step == len(cfg.KnockPorts)-1 {
		delete(s.seq, sourceIP)
		log.Printf("敲门序列完成：source=%s", sourceIP)
		return true
	}

	current.next++
	s.seq[sourceIP] = current
	return false
}

func (s *State) startOrComplete(cfg config.Config, sourceIP string, now time.Time) bool {
	if len(cfg.KnockPorts) == 1 {
		delete(s.seq, sourceIP)
		log.Printf("单步敲门完成：source=%s", sourceIP)
		return true
	}
	s.seq[sourceIP] = sequenceState{
		next:     1,
		deadline: now.Add(time.Duration(cfg.SeqTimeoutSeconds) * time.Second),
	}
	log.Printf("敲门序列开始：source=%s", sourceIP)
	return false
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
