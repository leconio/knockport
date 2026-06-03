package protocol

import (
	"bytes"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
)

const Version = "KG1"

// Payload 是客户端在最后一个 UDP 敲门端口发送的数据。
//
// 首选格式是 19 字节 compact binary：
//
//	K1 + step + unix_timestamp + nonce + truncated_hmac
//
// HMAC 输入额外包含目的端口：
//
//	K1 + udp_port + step + unix_timestamp + nonce
//
// Verify 仍兼容旧文本格式 KG1|step|unix_timestamp|nonce|hmac，便于旧客户端过渡。
//
// 前面的敲门包可以是任意短 payload；服务端只按 pcap 看到的端口顺序推进状态。
// 只有全部端口顺序正确之后，服务端才校验最后一个包的 HMAC，以降低 CPU 压力。
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
	if payload, ok := VerifyBytes(secret, port, []byte(raw), windowSeconds, now); ok {
		return payload, true
	}
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

func VerifyBytes(secret []byte, port int, raw []byte, windowSeconds int, now time.Time) (Payload, bool) {
	if len(raw) != 19 || !bytes.Equal(raw[:2], []byte("K1")) {
		return Payload{}, false
	}
	step := int(raw[2])
	ts := int64(binary.BigEndian.Uint32(raw[3:7]))
	nonceBytes := raw[7:11]
	if math.Abs(float64(now.Unix()-ts)) > float64(windowSeconds) {
		return Payload{}, false
	}
	msg := compactMessage(port, step, uint32(ts), nonceBytes)
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write(msg)
	expected := mac.Sum(nil)[:8]
	if !hmac.Equal(expected, raw[11:19]) {
		return Payload{}, false
	}
	return Payload{Step: step, Time: ts, Nonce: base64.RawURLEncoding.EncodeToString(nonceBytes), MAC: base64.RawURLEncoding.EncodeToString(raw[11:19])}, true
}

func sign(secret []byte, port int, step int, ts int64, nonce string) string {
	mac := hmac.New(sha256.New, secret)
	_, _ = mac.Write([]byte(fmt.Sprintf("%s|%d|%d|%d|%s", Version, port, step, ts, nonce)))
	sum := mac.Sum(nil)
	return base64.RawURLEncoding.EncodeToString(sum[:16])
}

func newNonce() (string, error) {
	buf := make([]byte, 12)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(buf), nil
}

func compactMessage(port int, step int, ts uint32, nonce []byte) []byte {
	buf := make([]byte, 0, 13)
	buf = append(buf, 'K', '1')
	var portBuf [2]byte
	binary.BigEndian.PutUint16(portBuf[:], uint16(port))
	buf = append(buf, portBuf[:]...)
	buf = append(buf, byte(step))
	var tsBuf [4]byte
	binary.BigEndian.PutUint32(tsBuf[:], ts)
	buf = append(buf, tsBuf[:]...)
	buf = append(buf, nonce...)
	return buf
}
