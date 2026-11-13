package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestFixedAddressAndAuthorizationValidation(t *testing.T) {
	for _, name := range []string{"camera.example.ts.net", "CAMERA.example.ts.net."} {
		a, e := funnelAddress(name)
		if e != nil || a != "https://camera.example.ts.net" {
			t.Fatal(name, e)
		}
	}
	for _, name := range []string{"example.com", "localhost", "ts.net", "camera.other.ts.net.evil.test", "camera..ts.net", "-camera.example.ts.net", "camera.example.ts.net/path", "camera.example.ts.net:443", "user@camera.example.ts.net", "camera.example.ts.net\r\nX: bad"} {
		if _, e := funnelAddress(name); e == nil {
			t.Fatal("accepted invalid name", name)
		}
	}
	good := "https://login.tailscale.com/f/funnel?fixture-secret=private"
	if authorizationLink("Open "+good) != good {
		t.Fatal("authorization link missing")
	}
	for _, bad := range []string{"http://login.tailscale.com/x", "https://evil.test/x", "https://login.tailscale.com.evil.test/x", "https://secret@login.tailscale.com/x", "javascript:alert(1)"} {
		if authorizationLink(bad) != "" {
			t.Fatal("untrusted authorization link")
		}
	}
	out := &boundedOutput{}
	if _, e := out.Write(bytes.Repeat([]byte{'x'}, 1024*1024+1)); e == nil || out.Len() != 0 {
		t.Fatal("unbounded status output")
	}
	args := strings.Join(fixedTunnelArgs("http://127.0.0.1:9234"), " ")
	if args != "funnel --https=443 http://127.0.0.1:9234" {
		t.Fatal("persistent/overwriting funnel config", args)
	}
}
func TestFixedPublicListenerProtectsLocalSetupAndAuthentication(t *testing.T) {
	b := testBridge(t)
	secret := "https://login.tailscale.com/f/funnel?fixture-private"
	b.tunnelAuthorization = secret
	h := fixedPublicHandler(b.handler(), "https://camera.example.ts.net")
	call := func(method, path, origin string, data any, cookie *http.Cookie, csrf string) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(data)
		r := httptest.NewRequest(method, "http://127.0.0.1:9090"+path, bytes.NewReader(raw))
		r.Host = "localhost:9090" // Model a malicious Host or a proxy rewriting Host.
		r.Header.Set("Content-Type", "application/json")
		r.Header.Set("X-Setup", b.setupNonce)
		r.Header.Set("Origin", origin)
		r.Header.Set("X-CSRF", csrf)
		if cookie != nil {
			r.AddCookie(cookie)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	for _, path := range []string{"/setup", "/setup.html", "/setup.js"} {
		if call("GET", path, "", nil, nil, "").Code != 404 {
			t.Fatal("local page exposed", path)
		}
	}
	for _, path := range []string{"/api/local-status", "/api/setup"} {
		if call("POST", path, "https://camera.example.ts.net", map[string]any{}, nil, "").Code != 403 {
			t.Fatal("local API exposed", path)
		}
	}
	if call("GET", "/hls/live.m3u8", "", nil, nil, "").Code != 401 {
		t.Fatal("anonymous media")
	}
	if call("POST", "/api/login", "http://localhost:9090", map[string]string{"password": "remote-fixture-password"}, nil, "").Code != 403 {
		t.Fatal("forged origin")
	}
	w := call("POST", "/api/login", "https://camera.example.ts.net", map[string]string{"password": "remote-fixture-password"}, nil, "")
	if w.Code != 200 {
		t.Fatal("public login", w.Code)
	}
	cookie := w.Result().Cookies()[0]
	if !cookie.Secure || !cookie.HttpOnly {
		t.Fatal("public cookie security")
	}
	var login map[string]string
	json.Unmarshal(w.Body.Bytes(), &login)
	w = call("GET", "/api/status", "", nil, cookie, "")
	if w.Code != 200 || strings.Contains(w.Body.String(), "fixture-private") || strings.Contains(w.Body.String(), b.cfg.Password) {
		t.Fatal("public status leak")
	}
	if call("POST", "/api/viewer-heartbeat", "https://evil.test", map[string]any{}, cookie, login["csrf"]).Code != 403 {
		t.Fatal("cross-origin lease")
	}
	if call("POST", "/api/viewer-heartbeat", "https://camera.example.ts.net", map[string]any{}, cookie, login["csrf"]).Code != 200 {
		t.Fatal("public lease")
	}
	w = req(b, "GET", "/api/local-status", "127.0.0.1:9090", nil, nil, "")
	if w.Code != 403 {
		t.Fatal("local status missing nonce")
	}
	r := httptest.NewRequest("GET", "http://127.0.0.1:9090/api/local-status", nil)
	r.Header.Set("X-Setup", b.setupNonce)
	w = httptest.NewRecorder()
	b.handler().ServeHTTP(w, r)
	if w.Code != 200 || !strings.Contains(w.Body.String(), "fixture-private") {
		t.Fatal("local authorization link unavailable")
	}
}
