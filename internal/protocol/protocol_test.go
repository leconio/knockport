package protocol

import (
	"encoding/base64"
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
