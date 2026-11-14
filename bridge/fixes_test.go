package main

import (
	"bufio"
	"fmt"
	"io"
	"net"
	"net/textproto"
	"os"
	"os/exec"
	"path/filepath"
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

// Reconnect replaces a hung converter, while repeated play requests preserve
// the fresh converter shared by foreground viewers and motion monitoring.
func TestReconnectReplacesOnlyStaleConverter(t *testing.T) {
	for _, scenario := range []struct {
		name     string
		age      time.Duration
		playlist bool
		restart  bool
	}{
		{"live", time.Second, true, false},
		{"stalled", 30 * time.Second, true, true},
		{"startup_grace", 20 * time.Second, false, false},
		{"startup_stuck", 55 * time.Second, false, true},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			dir := t.TempDir()
			now := time.Now()
			calls := 0
			s := &streamManager{dir: dir, binary: "missing", cmd: exec.Command("unused"), started: now.Add(-scenario.age), cfg: Config{Host: "127.0.0.1", Port: 554, Path: "/onvif2"}, launch: func(*exec.Cmd) error { calls++; return exec.ErrNotFound }}
			if scenario.playlist {
				p := filepath.Join(dir, "live.m3u8")
				if err := os.WriteFile(p, []byte("#EXTM3U\n"), 0600); err != nil {
					t.Fatal(err)
				}
				if err := os.Chtimes(p, now.Add(-scenario.age), now.Add(-scenario.age)); err != nil {
					t.Fatal(err)
				}
			}
			available, code := s.status()
			if scenario.restart && (available || code != "video_sem_progresso" || s.diagnostic().Stage != "video_sem_progresso") {
				t.Fatal("stale video reported live", available, code)
			}
			err := s.start()
			if scenario.restart {
				if err == nil || calls != 1 {
					t.Fatal("reconnect did not replace stuck process", calls, err)
				}
			} else if err != nil || calls != 0 {
				t.Fatal("healthy or starting converter restarted", calls, err)
			}
		})
	}
}

// A generic converter failure must not erase an earlier camera socket error.
func TestCameraConnectionFailureSurvivesConverterExit(t *testing.T) {
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().(*net.TCPAddr)
	listener.Close()
	s := &streamManager{dir: t.TempDir(), binary: "unused", cfg: Config{Host: "127.0.0.1", Port: address.Port, Path: "/onvif2"}}
	s.launch = func(cmd *exec.Cmd) error {
		var relayURL string
		for _, arg := range cmd.Args {
			if strings.HasPrefix(arg, "rtsp://") {
				relayURL = arg
				break
			}
		}
		executable, err := os.Executable()
		if err != nil {
			return err
		}
		cmd.Path = executable
		cmd.Err = nil
		cmd.Args = []string{executable, "-test.run=^TestCameraFailureHelper$"}
		cmd.Env = append(os.Environ(), "NINHO_RELAY_TEST=1", "NINHO_TEST_RELAY_URL="+relayURL)
		return cmd.Start()
	}
	defer s.stop()
	if err := s.start(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-s.done:
	case <-time.After(5 * time.Second):
		t.Fatal("converter fixture timed out")
	}
	available, code := s.status()
	d := s.diagnostic()
	if available || code != "camera_recusou_conexao" || !d.RelayAccepted || d.CameraConnected || d.CameraError != code || d.Hint != "video_nao_identificado" || d.ExitCode == nil || *d.ExitCode != 1 {
		t.Fatalf("camera cause lost: %v %s %+v", available, code, d)
	}
	if got := cameraConnectionError(&net.OpError{Op: "dial", Err: os.ErrDeadlineExceeded}); got != "camera_sem_resposta" {
		t.Fatal(got)
	}
}
func TestCameraFailureHelper(t *testing.T) {
	if os.Getenv("NINHO_RELAY_TEST") != "1" {
		return
	}
	target := strings.Split(strings.TrimPrefix(os.Getenv("NINHO_TEST_RELAY_URL"), "rtsp://"), "/")[0]
	c, err := net.DialTimeout("tcp", target, time.Second)
	if err != nil {
		os.Exit(2)
	}
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	io.Copy(io.Discard, c)
	c.Close()
	fmt.Fprintln(os.Stderr, "Invalid data found when processing input")
	os.Exit(1)
}
