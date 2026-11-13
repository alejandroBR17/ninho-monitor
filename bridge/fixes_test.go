package main

import (
	"bufio"
	"net"
	"net/textproto"
	"os/exec"
	"strings"
	"testing"
	"time"
)

func TestSessionProbeAndPublicAssets(t *testing.T) {
	b := testBridge(t)
	w := req(b, "GET", "/api/session", "viewer.test", nil, nil, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"authenticated":false`) || strings.Contains(w.Body.String(), "csrf") {
		t.Fatal("anonymous session probe", w.Code, w.Body.String())
	}
	cookie, _ := login(t, b)
	w = req(b, "GET", "/api/session", "viewer.test", nil, cookie, "")
	if w.Code != 200 || !strings.Contains(w.Body.String(), `"authenticated":true`) {
		t.Fatal("authenticated probe")
	}
	w = req(b, "GET", "/favicon.ico", "viewer.test", nil, nil, "")
	if w.Code != 200 || !strings.Contains(w.Header().Get("Content-Type"), "image/png") {
		t.Fatal("favicon", w.Code)
	}
	w = req(b, "GET", "/", "viewer.test", nil, nil, "")
	if !strings.Contains(w.Body.String(), `name="mobile-web-app-capable"`) {
		t.Fatal("mobile metadata")
	}
}
func TestCameraWireCompatibility(t *testing.T) {
	r := bufio.NewReader(strings.NewReader("\r\nRTSP/1.0 200 OK\r\nCSeq: 4\r\n\r\n$\x00\x00\x03abc"))
	w, e := readWire(r)
	if e != nil || w.h.Get("Cseq") != "4" {
		t.Fatal("leading camera CRLF", e)
	}
	w, e = readWire(r)
	if e != nil || string(w.frame) != "$\x00\x00\x03abc" {
		t.Fatal("RTP bytes changed", e)
	}
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	go writeWire(a, wire{line: "OPTIONS rtsp://camera/onvif1 RTSP/1.0", h: textproto.MIMEHeader{"Cseq": []string{"7"}}})
	line := bufio.NewReader(b)
	line.ReadString('\n')
	header, _ := line.ReadString('\n')
	if header != "CSeq: 7\r\n" {
		t.Fatal("camera header spelling", header)
	}
	cfg := Config{Host: "192.168.1.100", Port: 554}
	got := rewriteCameraURIs("a=control:rtsp://192.168.1.100/onvif1/track1\r\na=control:rtsp://192.168.1.17/onvif1", cfg, "rtsp://127.0.0.1:9000/private")
	if !strings.Contains(got, "rtsp://127.0.0.1:9000/private/onvif1/track1") || !strings.Contains(got, "rtsp://192.168.1.17/onvif1") {
		t.Fatal("default RTSP port rewrite", got)
	}
}
func TestStatusDuringSlowProcessLaunch(t *testing.T) {
	entered, release, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	s := &streamManager{dir: t.TempDir(), binary: "missing", cfg: Config{Host: "127.0.0.1", Port: 554, Path: "/onvif2"}, launch: func(*exec.Cmd) error { close(entered); <-release; return exec.ErrNotFound }}
	go func() { s.start(); close(finished) }()
	<-entered
	responsive := make(chan struct{})
	go func() { s.status(); s.diagnostic(); close(responsive) }()
	select {
	case <-responsive:
	case <-time.After(time.Second):
		close(release)
		t.Fatal("status blocked by Windows process launch")
	}
	close(release)
	<-finished
	_, code := s.status()
	if code != "conversor_nao_iniciou" {
		t.Fatal(code)
	}
	if classifyConverterError("rtsp://user:secret@camera:554/onvif1: Connection refused") != "camera_recusou_conexao" {
		t.Fatal("safe error classification")
	}
}
