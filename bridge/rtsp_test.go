package main

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"testing"
	"time"
)

func TestTransportOnlyNormalizesMatchingChannels(t *testing.T) {
	asked := "RTP/AVP/TCP;unicast;interleaved=0-1"
	for _, test := range []struct{ in, out string }{{"RTP/AVP;unicast;interleaved=0-1", "RTP/AVP/TCP;unicast;interleaved=0-1"}, {"RTP/AVP;interleaved=2-3", "RTP/AVP;interleaved=2-3"}, {"RTP/AVP;unicast", "RTP/AVP;unicast"}} {
		if got := normalizeTransport(test.in, asked); got != test.out {
			t.Fatal(got)
		}
	}
}
func TestRelayDigestAndInterleavedBytes(t *testing.T) {
	camera, e := net.Listen("tcp4", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	defer camera.Close()
	host, port, _ := net.SplitHostPort(camera.Addr().String())
	nport := 0
	fmt.Sscan(port, &nport)
	cfg := Config{Host: host, Port: nport, Path: "/onvif2", User: "fixture", Password: "fixture-secret"}
	relay, e := newRelay(cfg)
	if e != nil {
		t.Fatal(e)
	}
	defer relay.close()
	result := make(chan error, 1)
	go func() {
		result <- func() error {
			c, e := camera.Accept()
			if e != nil {
				return e
			}
			defer c.Close()
			c.SetDeadline(time.Now().Add(4 * time.Second))
			r := bufio.NewReader(c)
			w, e := readWire(r)
			if e != nil {
				return e
			}
			target := cfg.cameraURL().String()
			if !strings.Contains(w.line, target) || w.h.Get("Authorization") != "" {
				return fmt.Errorf("initial request")
			}
			c.Write([]byte("RTSP/1.0 401 Unauthorized\r\nCSeq: 1\r\nWWW-Authenticate: Digest realm=\"fixture\",nonce=\"nonce\"\r\n\r\n"))
			w, e = readWire(r)
			if e != nil {
				return e
			}
			auth := w.h.Get("Authorization")
			expected := md5hex(md5hex("fixture:fixture:fixture-secret") + ":nonce:" + md5hex("DESCRIBE:"+target))
			if !strings.Contains(auth, expected) || strings.Contains(auth, "fixture-secret") {
				return fmt.Errorf("digest mismatch")
			}
			body := "v=0\r\na=control:" + target + "/track1\r\n"
			c.Write([]byte(fmt.Sprintf("RTSP/1.0 200 OK\r\nCSeq: 1\r\nContent-Base: %s/\r\nContent-Length: %d\r\n\r\n%s", target, len(body), body)))
			w, e = readWire(r)
			if e != nil {
				return e
			}
			if !strings.Contains(w.line, target+"/track1") {
				return fmt.Errorf("setup rewrite")
			}
			c.Write([]byte("RTSP/1.0 200 OK\r\nCSeq: 2\r\nTransport: RTP/AVP;unicast;interleaved=0-1\r\n\r\n"))
			c.Write([]byte{'$', 0, 0, 3, 'a', 'b', 'c'})
			return nil
		}()
	}()
	client, e := net.Dial("tcp", relay.listener.Addr().String())
	if e != nil {
		t.Fatal(e)
	}
	defer client.Close()
	client.SetDeadline(time.Now().Add(4 * time.Second))
	fmt.Fprintf(client, "DESCRIBE %s RTSP/1.0\r\nCSeq: 1\r\n\r\n", relay.url())
	r := bufio.NewReader(client)
	w, e := readWire(r)
	if e != nil {
		t.Fatal(e)
	}
	if !strings.Contains(w.line, "200") || !strings.Contains(string(w.body), relay.url()+"/track1") {
		t.Fatal("response mapping")
	}
	fmt.Fprintf(client, "SETUP %s/track1 RTSP/1.0\r\nCSeq: 2\r\nTransport: RTP/AVP/TCP;unicast;interleaved=0-1\r\n\r\n", relay.url())
	w, e = readWire(r)
	if e != nil || !strings.HasPrefix(w.h.Get("Transport"), "RTP/AVP/TCP") {
		t.Fatal("transport normalization", e)
	}
	w, e = readWire(r)
	if e != nil || string(w.frame) != "$\x00\x00\x03abc" {
		t.Fatal("interleaved corruption")
	}
	if e = <-result; e != nil {
		t.Fatal(e)
	}
}
