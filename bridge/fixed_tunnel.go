package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// Only state codes, the public address and a local-only authorization link are
// retained. CLI output may include account information and is never logged.
func (b *bridge) tunnelUpdate(state, address, authorization string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.tunnelState = state
	b.publicURL = address
	b.tunnelAuthorization = authorization
}
func tailscaleBinary() (string, error) {
	if p, e := exec.LookPath("tailscale"); e == nil {
		return p, nil
	}
	for _, base := range []string{os.Getenv("ProgramFiles"), os.Getenv("ProgramW6432")} {
		if base != "" {
			p := filepath.Join(base, "Tailscale", "tailscale.exe")
			if st, e := os.Stat(p); e == nil && !st.IsDir() {
				return p, nil
			}
		}
	}
	return "", errors.New("tailscale_ausente")
}

var dnsLabel = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$`)

func funnelAddress(name string) (string, error) {
	name = strings.TrimSuffix(strings.ToLower(name), ".")
	labels := strings.Split(name, ".")
	if len(name) > 253 || len(labels) < 4 || !strings.HasSuffix(name, ".ts.net") {
		return "", errors.New("nome_tailscale_indisponivel")
	}
	for _, label := range labels {
		if !dnsLabel.MatchString(label) {
			return "", errors.New("nome_tailscale_indisponivel")
		}
	}
	return "https://" + name, nil
}

type boundedOutput struct{ bytes.Buffer }

func (w *boundedOutput) Write(p []byte) (int, error) {
	if w.Len()+len(p) > 1024*1024 {
		return 0, errors.New("resposta_tailscale_grande")
	}
	return w.Buffer.Write(p)
}
func tailscaleAddress(ctx context.Context, binary string) (string, error) {
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, binary, "status", "--json")
	var output boundedOutput
	cmd.Stdout = &output
	cmd.Stderr = io.Discard
	if e := cmd.Start(); e != nil {
		return "", errors.New("tailscale_sem_resposta")
	}
	if e := attachProcess(cmd); e != nil {
		cmd.Process.Kill()
		cmd.Wait()
		return "", errors.New("processo_windows_nao_protegido")
	}
	if e := cmd.Wait(); e != nil {
		return "", errors.New("tailscale_sem_resposta")
	}
	var status struct {
		BackendState string
		Self         *struct{ DNSName string }
	}
	if json.Unmarshal(output.Bytes(), &status) != nil {
		return "", errors.New("tailscale_sem_resposta")
	}
	if status.BackendState != "Running" || status.Self == nil {
		return "", errors.New("entrar_no_tailscale")
	}
	return funnelAddress(status.Self.DNSName)
}

// Funnel reaches a separate ephemeral loopback listener. Even a forged Host or
// X-Setup header cannot expose the local setup API through that listener.
func fixedPublicHandler(next http.Handler, address string) http.Handler {
	public, e := url.Parse(address)
	if e != nil || public.Scheme != "https" || public.Host == "" || public.User != nil || public.Path != "" || public.RawQuery != "" || public.Fragment != "" || public.Port() != "" {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fail(w, 503, "endereco_fixo_invalido") })
	}
	expected, err := funnelAddress(public.Hostname())
	if err != nil || expected != address {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fail(w, 503, "endereco_fixo_invalido") })
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		switch r.URL.Path {
		case "/setup", "/setup.html", "/setup.js":
			http.NotFound(w, r)
			return
		case "/api/setup", "/api/local-status":
			fail(w, 403, "painel_local_apenas")
			return
		}
		clone := r.Clone(r.Context())
		clone.Host = public.Host
		clone.Header.Del("X-Setup")
		next.ServeHTTP(w, clone)
	})
}
func authorizationLink(line string) string {
	for _, word := range strings.Fields(line) {
		candidate := strings.Trim(word, "()[]<>,")
		u, e := url.Parse(candidate)
		if e == nil && u.Scheme == "https" && u.Host == "login.tailscale.com" && u.User == nil && u.Path != "" {
			return u.String()
		}
	}
	return ""
}
func fixedTunnelArgs(origin string) []string {
	// No --bg, reset or off: the daemon ties this foreground configuration to the
	// CLI's watcher session and removes it when that process disconnects.
	return []string{"funnel", "--https=443", origin}
}
func startFixedTunnel(ctx context.Context, b *bridge) {
	b.mu.Lock()
	b.remoteMode = "fixo_tailscale"
	b.mu.Unlock()
	binary, e := tailscaleBinary()
	if e != nil {
		b.tunnelUpdate("tailscale_ausente", "", "")
		fmt.Println("Endereço fixo: instale o Tailscale no Windows e entre no plano Personal gratuito. Depois reabra INICIAR-COM-ENDERECO-FIXO.cmd.")
		return
	}
	address, e := tailscaleAddress(ctx, binary)
	if e != nil {
		b.tunnelUpdate(e.Error(), "", "")
		fmt.Println("Endereço fixo: confira se o Tailscale está aberto e conectado à sua conta. Depois reabra este atalho.")
		return
	}
	listener, e := net.Listen("tcp4", "127.0.0.1:0")
	if e != nil {
		b.tunnelUpdate("porta_fixa_indisponivel", "", "")
		return
	}
	origin := "http://" + listener.Addr().String()
	server := &http.Server{Handler: fixedPublicHandler(b.handler(), address), ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	defer server.Close()
	go server.Serve(listener)
	// This listener also closes promptly if the main bridge is shutting down.
	done := make(chan struct{})
	defer close(done)
	go func() {
		select {
		case <-ctx.Done():
			server.Close()
		case <-done:
		}
	}()
	for attempt := 0; attempt < 4; attempt++ {
		if ctx.Err() != nil {
			return
		}
		b.tunnelUpdate("iniciando_fixo", "", "")
		cmd := exec.CommandContext(ctx, binary, fixedTunnelArgs(origin)...)
		authorization := ""
		announced := false
		sink := &lineSink{line: func(line string) {
			if link := authorizationLink(line); link != "" {
				authorization = link
				b.tunnelUpdate("autorizar_funnel", "", link)
				return
			}
			if strings.TrimSuffix(strings.TrimSpace(line), "/") == address {
				announced = true
				authorization = ""
				b.tunnelUpdate("fixo_configurado", address, "")
				fmt.Println("\nENDEREÇO FIXO: " + address + "\nUse sua senha remota. O endereço é mantido enquanto o nome do notebook e da rede Tailscale forem os mesmos.")
			}
		}}
		cmd.Stdout = sink
		cmd.Stderr = sink
		if e = cmd.Start(); e != nil {
			b.tunnelUpdate("tailscale_sem_resposta", "", "")
			return
		}
		if e = attachProcess(cmd); e != nil {
			cmd.Process.Kill()
			cmd.Wait()
			b.tunnelUpdate("processo_windows_nao_protegido", "", "")
			return
		}
		cmd.Wait()
		if ctx.Err() != nil {
			return
		}
		if authorization != "" {
			b.tunnelUpdate("autorizar_funnel", "", authorization)
			fmt.Println("Autorize o Funnel pelo botão no painel local. Depois reabra o atalho de endereço fixo.")
			return
		}
		if !announced {
			b.tunnelUpdate("funnel_nao_iniciou", "", "")
			fmt.Println("O Funnel não iniciou. Confira a conexão do Tailscale e se já existe outro serviço usando a porta HTTPS 443. Não alteramos serviços existentes.")
			return
		}
		b.tunnelUpdate("fixo_interrompido", "", "")
		if attempt == 3 {
			fmt.Println("Endereço fixo interrompido. Confira o Tailscale e reabra a ponte.")
			return
		}
		timer := time.NewTimer([]time.Duration{time.Second, 3 * time.Second, 10 * time.Second}[attempt])
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
}
