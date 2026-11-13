//go:build !windows

package main

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func fakeTailscale(t *testing.T, status, address, authorization string) string {
	t.Helper()
	dir := t.TempDir()
	p := filepath.Join(dir, "tailscale")
	script := `#!/bin/sh
if [ "$1" = "status" ]; then
 printf '%s' "$JORTAN_FIXTURE_STATUS"
 exit 0
fi
if [ -n "$JORTAN_FIXTURE_AUTH" ]; then
 printf '%s\n' "$JORTAN_FIXTURE_AUTH"
 exit 0
fi
printf '%s' "$3" > "$JORTAN_FIXTURE_TARGET"
printf '%s\n' "$JORTAN_FIXTURE_ADDRESS"
exec /bin/sleep 30
`
	if e := os.WriteFile(p, []byte(script), 0700); e != nil {
		t.Fatal(e)
	}
	target := filepath.Join(dir, "target")
	t.Setenv("PATH", dir)
	t.Setenv("JORTAN_FIXTURE_STATUS", status)
	t.Setenv("JORTAN_FIXTURE_ADDRESS", address)
	t.Setenv("JORTAN_FIXTURE_AUTH", authorization)
	t.Setenv("JORTAN_FIXTURE_TARGET", target)
	return target
}
func TestFixedTunnelProcessLifecycle(t *testing.T) {
	target := fakeTailscale(t, `{"BackendState":"Running","Self":{"DNSName":"camera.example.ts.net."},"User":{"fixture":"not-retained"}}`, "https://camera.example.ts.net/", "")
	b := testBridge(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() { startFixedTunnel(ctx, b); close(done) }()
	deadline := time.Now().Add(5 * time.Second)
	for {
		b.mu.Lock()
		ready := b.publicURL == "https://camera.example.ts.net"
		b.mu.Unlock()
		if ready {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("funnel did not announce")
		}
		time.Sleep(10 * time.Millisecond)
	}
	raw, e := os.ReadFile(target)
	if e != nil {
		t.Fatal(e)
	}
	client := &http.Client{Timeout: time.Second}
	r, e := client.Get(string(raw) + "/api/local-status")
	if e != nil {
		t.Fatal(e)
	}
	r.Body.Close()
	if r.StatusCode != 403 {
		t.Fatal("funnel exposed setup")
	}
	cancel()
	select {
	case <-done:
	case <-time.After(3 * time.Second):
		t.Fatal("funnel process not stopped")
	}
	if r, e = client.Get(string(raw) + "/"); e == nil {
		r.Body.Close()
		t.Fatal("public listener survived shutdown")
	}
}
func TestFixedTunnelRequiresLoginAndKeepsAuthorizationLocal(t *testing.T) {
	fakeTailscale(t, `{"BackendState":"NeedsLogin","Self":null}`, "", "")
	binary, _ := tailscaleBinary()
	if _, e := tailscaleAddress(context.Background(), binary); e == nil || e.Error() != "entrar_no_tailscale" {
		t.Fatal("login requirement", e)
	}
	t.Setenv("JORTAN_FIXTURE_STATUS", `{"BackendState":"Running","Self":{"DNSName":"camera.example.ts.net."}}`)
	secret := "https://login.tailscale.com/f/funnel?fixture-secret"
	t.Setenv("JORTAN_FIXTURE_AUTH", secret)
	b := testBridge(t)
	startFixedTunnel(context.Background(), b)
	if b.tunnelState != "autorizar_funnel" || b.tunnelAuthorization != secret || b.publicURL != "" {
		t.Fatal("authorization state")
	}
	if req(b, "GET", "/api/local-status", "camera.example.ts.net", nil, nil, "").Code != 403 {
		t.Fatal("authorization link exposed")
	}
}
