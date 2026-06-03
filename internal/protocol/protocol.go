package protocol

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
)

const Version = "KG1"

// Payload 是客户端发到每一个 UDP 敲门端口的数据。
//
// 格式：
//
//	KG1|step|unix_timestamp|nonce|hmac
//
// HMAC 输入额外包含目的端口：
//
//	KG1|udp_port|step|unix_timestamp|nonce
//
// 这样即使旁路观察者把同一个包转发到另一个端口，也无法通过校验。
type Payload struct {
	Step  int
	Time  int64
	Nonce string
	MAC   string
}

func Build(secret []byte, port int, step int, now time.Time) (string, error) {
	nonce, err := newNonce()
	if err != nil {
		return "", err
	}
	ts := now.Unix()
	mac := sign(secret, port, step, ts, nonce)
	return fmt.Sprintf("%s|%d|%d|%s|%s", Version, step, ts, nonce, mac), nil
}

func Verify(secret []byte, port int, raw string, windowSeconds int, now time.Time) (Payload, bool) {
	parts := strings.Split(strings.TrimSpace(raw), "|")
	if len(parts) != 5 || parts[0] != Version {
		return Payload{}, false
	}
	step, err := strconv.Atoi(parts[1])
	if err != nil || step < 0 {
		return Payload{}, false
	}
	ts, err := strconv.ParseInt(parts[2], 10, 64)
	if err != nil {
		return Payload{}, false
	}
	nonce := parts[3]
	if len(nonce) < 16 || len(nonce) > 128 {
		return Payload{}, false
	}
	if math.Abs(float64(now.Unix()-ts)) > float64(windowSeconds) {
		return Payload{}, false
	}
	expected := sign(secret, port, step, ts, nonce)
	if !hmac.Equal([]byte(expected), []byte(parts[4])) {
		return Payload{}, false
	}
	return Payload{Step: step, Time: ts, Nonce: nonce, MAC: parts[4]}, true
}

func sign(secret []byte, port int, step int, ts int64, nonce string) string {
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte(fmt.Sprintf("%s|%d|%d|%d|%s", Version, port, step, ts, nonce)))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func newNonce() (string, error) {
	buf := make([]byte, 18)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}
