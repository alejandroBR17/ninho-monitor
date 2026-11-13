package main

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	webpush "github.com/SherClockHolmes/webpush-go"
	"github.com/golang-jwt/jwt/v5"
)

func TestImageDetectorWarmupBrightnessMotionAndCooldown(t *testing.T) {
	var d imageDetector
	now := time.Unix(1000, 0)
	blank := make([]byte, frameSize)
	bright := bytes.Repeat([]byte{80}, frameSize)
	for i := 0; i < 10; i++ {
		frame := blank
		if i%2 == 1 {
			frame = bright
		}
		if d.frame(frame, now.Add(time.Duration(i)*time.Second), "normal") {
			t.Fatal("global brightness alerted")
		}
	}
	d.reset()
	for i := 0; i < 6; i++ {
		if d.frame(blank, now.Add(time.Duration(i)*time.Second), "normal") {
			t.Fatal("warmup alerted")
		}
	}
	box := append([]byte(nil), blank...)
	for y := 20; y < 60; y++ {
		for x := 20; x < 80; x++ {
			box[y*frameWidth+x] = 200
		}
	}
	detected := 0
	for i := 0; i < 12; i++ {
		f := blank
		if i%2 == 0 {
			f = box
		}
		if d.frame(f, now.Add(time.Duration(10+i)*time.Second), "normal") {
			detected++
		}
	}
	if detected != 1 {
		t.Fatal("motion/cooldown", detected)
	}
	d.reset()
	d.mutedUntil = now.Add(100 * time.Second)
	for i := 0; i < 20; i++ {
		f := blank
		if i%2 == 0 {
			f = box
		}
		if d.frame(f, now.Add(time.Duration(30+i)*time.Second), "high") {
			t.Fatal("PTZ suppression failed")
		}
	}
}
func TestRawFrameBoundariesAndDisabledDetector(t *testing.T) {
	var got [][]byte
	sink := &frameSink{frame: func(b []byte) { got = append(got, append([]byte(nil), b...)) }}
	data := append(bytes.Repeat([]byte{12}, frameSize), bytes.Repeat([]byte{99}, frameSize)...)
	for start := 0; start < len(data); {
		end := start + 713
		if end > len(data) {
			end = len(data)
		}
		sink.Write(data[start:end])
		start = end
	}
	if len(got) != 2 || !bytes.Equal(got[0], data[:frameSize]) || !bytes.Equal(got[1], data[frameSize:]) {
		t.Fatal("raw frames corrupted")
	}
	a := newAlerts(filepath.Join(t.TempDir(), "alerts.bin"), Config{})
	for i := 0; i < 12; i++ {
		a.frame(got[i%2])
	}
	if a.latest.ID != 0 || a.enabled() {
		t.Fatal("disabled monitor alerted")
	}
}

type pushFixture struct {
	request *http.Request
	body    []byte
	code    int
}

func (p *pushFixture) Do(r *http.Request) (*http.Response, error) {
	p.request = r
	p.body, _ = io.ReadAll(r.Body)
	return &http.Response{StatusCode: p.code, Body: io.NopCloser(strings.NewReader("fixture")), Header: make(http.Header)}, nil
}
func TestPushEncryptionOriginValidationAndExpiry(t *testing.T) {
	a := newAlerts(filepath.Join(t.TempDir(), "alerts.bin"), Config{})
	public, e := a.key()
	if e != nil || public == "" {
		t.Fatal("key generation")
	}
	ua, _ := ecdh.P256().GenerateKey(rand.Reader)
	auth := bytes.Repeat([]byte{7}, 16)
	s := webpush.Subscription{Endpoint: "https://fcm.googleapis.com/fcm/send/fixture", Keys: webpush.Keys{Auth: base64.RawURLEncoding.EncodeToString(auth), P256dh: base64.RawURLEncoding.EncodeToString(ua.PublicKey().Bytes())}}
	for _, endpoint := range []string{"http://fcm.googleapis.com/x", "https://127.0.0.1/x", "https://fcm.googleapis.com.evil.test/x", "https://user@web.push.apple.com/x", "https://web.push.apple.com:444/x"} {
		bad := s
		bad.Endpoint = endpoint
		if validSubscription(bad) {
			t.Fatal("untrusted push destination")
		}
	}
	if e = a.subscribe(s); e != nil {
		t.Fatal("valid subscription")
	}
	fixture := &pushFixture{code: 201}
	a.client = fixture
	if !a.test(context.Background(), s.Endpoint) {
		t.Fatal("push acceptance")
	}
	if fixture.request.Header.Get("Content-Encoding") != "aes128gcm" || fixture.request.Header.Get("TTL") != "60" {
		t.Fatal("push headers")
	}
	raw := fixture.body
	if bytes.Contains(raw, []byte("Alteração de imagem")) || len(raw) < 87 {
		t.Fatal("unencrypted payload")
	}
	salt := raw[:16]
	keyLen := int(raw[20])
	serverPublic := raw[21 : 21+keyLen]
	pubKey, e := ecdh.P256().NewPublicKey(serverPublic)
	if e != nil {
		t.Fatal("server ECDH")
	}
	shared, _ := ua.ECDH(pubKey)
	info := append([]byte("WebPush: info\x00"), ua.PublicKey().Bytes()...)
	info = append(info, serverPublic...)
	ikm, _ := hkdf.Key(sha256.New, shared, auth, string(info), 32)
	cek, _ := hkdf.Key(sha256.New, ikm, salt, "Content-Encoding: aes128gcm\x00", 16)
	nonce, _ := hkdf.Key(sha256.New, ikm, salt, "Content-Encoding: nonce\x00", 12)
	block, _ := aes.NewCipher(cek)
	gcm, _ := cipher.NewGCM(block)
	plain, e := gcm.Open(nil, nonce, raw[21+keyLen:], nil)
	if e != nil {
		t.Fatal("RFC8291 decryption")
	}
	plain = bytes.TrimRight(plain, "\x00")
	if plain[len(plain)-1] != 2 {
		t.Fatal("record delimiter")
	}
	var payload map[string]any
	if json.Unmarshal(plain[:len(plain)-1], &payload) != nil || payload["test"] != true {
		t.Fatal("push payload")
	}
	parts := strings.Split(fixture.request.Header.Get("Authorization"), ",")
	token := strings.TrimPrefix(strings.TrimSpace(parts[0]), "vapid t=")
	pk, _ := base64.RawURLEncoding.DecodeString(public)
	x, y := elliptic.Unmarshal(elliptic.P256(), pk)
	_, e = jwt.Parse(token, func(*jwt.Token) (any, error) { return &ecdsa.PublicKey{Curve: elliptic.P256(), X: x, Y: y}, nil }, jwt.WithValidMethods([]string{"ES256"}), jwt.WithAudience("https://fcm.googleapis.com"))
	if e != nil {
		t.Fatal("VAPID signature/audience")
	}
	fixture.code = 410
	if a.test(context.Background(), s.Endpoint) || len(a.cfg.Subscriptions) != 0 {
		t.Fatal("expired subscription retained")
	}
}
func TestAlertAPIProtectedPersistenceAndOwnerReset(t *testing.T) {
	b := testBridge(t)
	if req(b, "GET", "/api/alerts", "viewer.test", nil, nil, "").Code != 401 {
		t.Fatal("anonymous monitor")
	}
	cookie, csrf := login(t, b)
	if req(b, "POST", "/api/alerts/settings", "viewer.test", map[string]any{"enabled": true, "sensitivity": "normal"}, cookie, "").Code != 403 {
		t.Fatal("monitor without CSRF")
	}
	if req(b, "POST", "/api/alerts/settings", "viewer.test", map[string]any{"enabled": true, "sensitivity": "normal"}, cookie, csrf).Code != 200 {
		t.Fatal("enable monitor")
	}
	if req(b, "POST", "/api/alerts/key", "viewer.test", map[string]any{}, cookie, csrf).Code != 200 {
		t.Fatal("public push key")
	}
	raw := req(b, "GET", "/api/alerts", "viewer.test", nil, cookie, "").Body.String()
	if strings.Contains(raw, b.alerts.cfg.PrivateKey) || strings.Contains(raw, "privateKey") {
		t.Fatal("private push key exposed")
	}
	b.stream.cmd = &exec.Cmd{}
	b.stream.last = time.Now().Add(-120 * time.Second)
	if b.stream.expireIdle(time.Now()) {
		t.Fatal("active detector expired")
	}
	if e := b.alerts.settings(false, "normal"); e != nil {
		t.Fatal(e)
	}
	if !b.stream.expireIdle(time.Now()) {
		t.Fatal("disabled detector retained converter")
	}
	b.alerts.bind(b.cfg)
	if b.alerts.enabled() || len(b.alerts.cfg.Subscriptions) > 0 {
		t.Fatal("account change retained alerts")
	}
	reloaded := newAlerts(b.alerts.path, b.cfg)
	if reloaded.enabled() {
		t.Fatal("owner reset not persisted")
	}
}
