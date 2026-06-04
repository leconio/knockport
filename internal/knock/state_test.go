package knock

import (
	"fmt"
	"testing"
	"time"

	"github.com/leconio/knockport/internal/config"
	"github.com/leconio/knockport/internal/protocol"
)

func TestAcceptChecksHMACOnlyOnFinalStep(t *testing.T) {
	secret := []byte("12345678901234567890123456789012")
	cfg := config.Config{
		KnockPorts:        []int{30001, 30002, 30003},
		SeqTimeoutSeconds: 10,
		HMACWindowSeconds: 60,
	}
	now := time.Unix(1000, 0)
	state := NewState()

	if state.Accept(cfg, secret, "203.0.113.10", 30001, []byte("not-hmac"), now) {
		t.Fatal("first step must not open")
	}
	if state.Accept(cfg, secret, "203.0.113.10", 30002, []byte("still-not-hmac"), now.Add(time.Second)) {
		t.Fatal("middle step must not open")
	}
	finalPayload, err := protocol.Build(secret, 30003, 2, now.Add(2*time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if !state.Accept(cfg, secret, "203.0.113.10", 30003, []byte(finalPayload), now.Add(2*time.Second)) {
		t.Fatal("valid final HMAC should open")
	}
}

func TestAcceptRejectsBadFinalHMAC(t *testing.T) {
	secret := []byte("12345678901234567890123456789012")
	cfg := config.Config{
		KnockPorts:        []int{30001, 30002},
		SeqTimeoutSeconds: 10,
		HMACWindowSeconds: 60,
	}
	now := time.Unix(1000, 0)
	state := NewState()

	if state.Accept(cfg, secret, "203.0.113.10", 30001, []byte("anything"), now) {
		t.Fatal("first step must not open")
	}
	if state.Accept(cfg, secret, "203.0.113.10", 30002, []byte("bad-final"), now.Add(time.Second)) {
		t.Fatal("bad final HMAC must not open")
	}
}

func TestAcceptRejectsNewSequenceWhenStateTableIsFull(t *testing.T) {
	secret := []byte("12345678901234567890123456789012")
	cfg := config.Config{
		KnockPorts:        []int{30001, 30002},
		SeqTimeoutSeconds: 10,
		HMACWindowSeconds: 60,
	}
	now := time.Unix(1000, 0)
	state := NewState()
	for i := 0; i < maxSequenceStates; i++ {
		state.seq[fmt.Sprintf("198.51.100.%d", i)] = sequenceState{
			next:     1,
			deadline: now.Add(time.Minute),
		}
	}

	if state.Accept(cfg, secret, "203.0.113.200", 30001, []byte("start"), now) {
		t.Fatal("full state table must not open")
	}
	if _, exists := state.seq["203.0.113.200"]; exists {
		t.Fatal("full state table must reject new sequence state")
	}
}

func TestAcceptCleansExpiredStateWhenTableIsFull(t *testing.T) {
	secret := []byte("12345678901234567890123456789012")
	cfg := config.Config{
		KnockPorts:        []int{30001, 30002},
		SeqTimeoutSeconds: 10,
		HMACWindowSeconds: 60,
	}
	now := time.Unix(1000, 0)
	state := NewState()
	for i := 0; i < maxSequenceStates; i++ {
		state.seq[fmt.Sprintf("198.51.100.%d", i)] = sequenceState{
			next:     1,
			deadline: now.Add(-time.Second),
		}
	}

	if state.Accept(cfg, secret, "203.0.113.200", 30001, []byte("start"), now) {
		t.Fatal("first step must not open")
	}
	if _, exists := state.seq["203.0.113.200"]; !exists {
		t.Fatal("expired entries should be cleared so new sequence can start")
	}
}
