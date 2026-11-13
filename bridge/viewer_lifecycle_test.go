package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

func TestViewerLeaseAuthorizationAndIdleExpiry(t *testing.T) {
	b := testBridge(t)
	b.stream.last = time.Now().Add(-89 * time.Second)
	b.stream.cmd = &exec.Cmd{}
	os.MkdirAll(b.stream.dir, 0700)
	playlist := filepath.Join(b.stream.dir, "live.m3u8")
	os.WriteFile(playlist, []byte("#EXTM3U"), 0600)
	before := b.stream.last
	if req(b, "POST", "/api/viewer-heartbeat", "viewer.test", map[string]any{}, nil, "").Code != 401 {
		t.Fatal("anonymous lease")
	}
	if b.stream.last != before {
		t.Fatal("anonymous extended stream")
	}
	cookie, csrf := login(t, b)
	if req(b, "GET", "/api/viewer-heartbeat", "viewer.test", nil, cookie, csrf).Code != 405 {
		t.Fatal("GET renewed")
	}
	if req(b, "POST", "/api/viewer-heartbeat", "viewer.test", map[string]any{}, cookie, "").Code != 403 {
		t.Fatal("lease without CSRF")
	}
	if b.stream.last != before {
		t.Fatal("invalid request extended stream")
	}
	if req(b, "POST", "/api/viewer-heartbeat", "viewer.test", map[string]any{}, cookie, csrf).Code != 200 {
		t.Fatal("viewer renewal")
	}
	if !b.stream.last.After(before) || b.stream.expireIdle(time.Now().Add(2*time.Second)) {
		t.Fatal("active viewer expired")
	}
	if _, e := os.Stat(playlist); e != nil {
		t.Fatal("viewer playlist removed")
	}
	if !b.stream.expireIdle(time.Now().Add(91 * time.Second)) {
		t.Fatal("abandoned conversion retained")
	}
	if _, e := os.Stat(playlist); !os.IsNotExist(e) {
		t.Fatal("idle playlist not removed")
	}
	if req(b, "GET", "/hls/live.m3u8", "viewer.test", nil, cookie, "").Code != 404 {
		t.Fatal("expected expired playlist")
	}
	// A heartbeat maintains a current conversion; it cannot start one by itself.
	if req(b, "POST", "/api/viewer-heartbeat", "viewer.test", map[string]any{}, cookie, csrf).Code != 200 || b.stream.cmd != nil {
		t.Fatal("lease unexpectedly started video")
	}
}
