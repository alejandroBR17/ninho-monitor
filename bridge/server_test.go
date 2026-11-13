package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func testBridge(t *testing.T) *bridge {
	t.Helper()
	root := t.TempDir()
	b := newBridge(filepath.Join(root, "config.bin"), "missing-ffmpeg", root)
	c := Config{Host: "127.0.0.1", Port: 554, Path: "/onvif2", User: "fixture", Password: "camera-fixture-private", OnvifPort: 5000}
	configurePassword(&c, "remote-fixture-password")
	b.cfg = c
	b.configured = true
	return b
}
func req(b *bridge, method, path, host string, data any, cookie *http.Cookie, csrf string) *httptest.ResponseRecorder {
	var body io.Reader
	if data != nil {
		v, _ := json.Marshal(data)
		body = bytes.NewReader(v)
	}
	r := httptest.NewRequest(method, "https://"+host+path, body)
	r.Host = host
	r.Header.Set("Origin", "https://"+host)
	r.Header.Set("Content-Type", "application/json")
	if cookie != nil {
		r.AddCookie(cookie)
	}
	if csrf != "" {
		r.Header.Set("X-CSRF", csrf)
	}
	w := httptest.NewRecorder()
	b.handler().ServeHTTP(w, r)
	return w
}
func login(t *testing.T, b *bridge) (*http.Cookie, string) {
	t.Helper()
	w := req(b, "POST", "/api/login", "viewer.test", map[string]string{"password": "remote-fixture-password"}, nil, "")
	if w.Code != 200 {
		t.Fatal(w.Code, w.Body.String())
	}
	var data map[string]string
	json.Unmarshal(w.Body.Bytes(), &data)
	cookie := w.Result().Cookies()[0]
	if !cookie.Secure || !cookie.HttpOnly || cookie.SameSite != http.SameSiteStrictMode {
		t.Fatal("cookie protection")
	}
	return cookie, data["csrf"]
}
func TestAuthenticationAndMedia(t *testing.T) {
	b := testBridge(t)
	for _, path := range []string{"/api/status", "/hls/live.m3u8"} {
		if w := req(b, "GET", path, "viewer.test", nil, nil, ""); w.Code != 401 {
			t.Fatal(path, w.Code)
		}
	}
	cookie, csrf := login(t, b)
	if w := req(b, "POST", "/api/play", "viewer.test", map[string]string{}, cookie, ""); w.Code != 403 {
		t.Fatal("csrf bypass")
	}
	os.MkdirAll(b.stream.dir, 0700)
	os.WriteFile(filepath.Join(b.stream.dir, "live.m3u8"), []byte("#EXTM3U"), 0600)
	w := req(b, "GET", "/hls/live.m3u8", "viewer.test", nil, cookie, "")
	if w.Code != 200 || w.Header().Get("Cache-Control") != "no-store" {
		t.Fatal("media auth")
	}
	for _, path := range []string{"/api/status", "/", "/app.js"} {
		w = req(b, "GET", path, "viewer.test", nil, cookie, "")
		if strings.Contains(w.Body.String(), b.cfg.Password) || strings.Contains(w.Body.String(), b.cfg.Hash) {
			t.Fatal("credential leak")
		}
	}
	w = req(b, "POST", "/api/logout", "viewer.test", map[string]string{}, cookie, csrf)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	if req(b, "GET", "/api/status", "viewer.test", nil, cookie, "").Code != 401 {
		t.Fatal("logout not revoked")
	}
}
func TestRemoteSetupBlockedAndLoginLimit(t *testing.T) {
	b := testBridge(t)
	for _, path := range []string{"/setup", "/setup.html", "/setup.js"} {
		if w := req(b, "GET", path, "viewer.test", nil, nil, ""); w.Code != 404 {
			t.Fatal("remote setup exposed", path, w.Code)
		}
	}
	if req(b, "POST", "/api/setup", "viewer.test", map[string]string{}, nil, "").Code != 403 {
		t.Fatal("remote setup write")
	}
	for n := 0; n < 6; n++ {
		w := req(b, "POST", "/api/login", "viewer.test", map[string]string{"password": "wrong"}, nil, "")
		expected := 401
		if n == 5 {
			expected = 429
		}
		if w.Code != expected {
			t.Fatal(n, w.Code)
		}
	}
}
func TestOriginAndConfigValidation(t *testing.T) {
	b := testBridge(t)
	r := httptest.NewRequest("POST", "https://viewer.test/api/login", strings.NewReader(`{"password":"remote-fixture-password"}`))
	r.Header.Set("Origin", "https://attacker.test")
	r.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	b.handler().ServeHTTP(w, r)
	if w.Code != 403 {
		t.Fatal("origin bypass")
	}
	for _, host := range []string{"8.8.8.8", "example.test", "127.0.0.1@attacker"} {
		c := b.cfg
		c.Host = host
		if c.valid() {
			t.Fatal("invalid target")
		}
	}
	if _, e := tree([]byte(`<!DOCTYPE x [<!ENTITY e SYSTEM "file:///secret">]><x>&e;</x>`)); e == nil {
		t.Fatal("DTD allowed")
	}
}
