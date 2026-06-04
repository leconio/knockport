package protocol

import (
	"encoding/base64"
	"encoding/hex"
	"os"
	"testing"
	"time"
)

func TestBuildVerify(t *testing.T) {
	secret := []byte("12345678901234567890123456789012")
	raw, err := Build(secret, 37708, 2, time.Unix(1000, 0))
	if err != nil {
		t.Fatal(err)
	}
	payload, ok := Verify(secret, 37708, raw, 60, time.Unix(1001, 0))
	if !ok {
		t.Fatal("expected valid payload")
	}
	if payload.Step != 2 {
		t.Fatalf("step = %d", payload.Step)
	}
}

func TestVerifyRejectsWrongPort(t *testing.T) {
	secret := []byte("12345678901234567890123456789012")
	raw, err := Build(secret, 37708, 0, time.Unix(1000, 0))
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := Verify(secret, 37709, raw, 60, time.Unix(1000, 0)); ok {
		t.Fatal("expected wrong destination port to fail")
	}
}

func TestSecretEncodingShape(t *testing.T) {
	secret := base64.RawURLEncoding.EncodeToString([]byte("12345678901234567890123456789012"))
	if secret == "" {
		t.Fatal("empty secret")
	}
}

func TestExternalCompactPayload(t *testing.T) {
	secretText := os.Getenv("KNOCKGATE_TEST_SECRET")
	payloadHex := os.Getenv("KNOCKGATE_TEST_PAYLOAD_HEX")
	if secretText == "" || payloadHex == "" {
		t.Skip("external payload not provided")
	}
	secret, err := base64.RawURLEncoding.DecodeString(secretText)
	if err != nil {
		t.Fatal(err)
	}
	payload, err := hex.DecodeString(payloadHex)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := VerifyBytes(secret, 59462, payload, 3600, time.Now()); !ok {
		t.Fatalf("payload did not verify")
	}
}

func TestBuildCompactVerifies(t *testing.T) {
	secret := []byte("12345678901234567890123456789012")
	now := time.Unix(1000, 0)
	raw, err := BuildCompact(secret, 37708, 5, now)
	if err != nil {
		t.Fatal(err)
	}
	if len(raw) != 19 {
		t.Fatalf("payload length = %d", len(raw))
	}
	payload, ok := VerifyBytes(secret, 37708, raw, 60, now)
	if !ok {
		t.Fatal("expected compact payload to verify")
	}
	if payload.Step != 5 {
		t.Fatalf("step = %d", payload.Step)
	}
}
