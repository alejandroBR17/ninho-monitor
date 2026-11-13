package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

func main() {
	port := flag.Int("port", 9090, "Porta local da ponte")
	local := flag.Bool("local-only", false, "Executar sem publicar túnel")
	fixed := flag.Bool("endereco-fixo", false, "Usar endereço gratuito Tailscale Funnel")
	flag.Parse()
	exe, _ := os.Executable()
	base := filepath.Dir(exe)
	root, e := os.UserConfigDir()
	if e != nil {
		fmt.Println("Não foi possível abrir os dados locais.")
		return
	}
	if local := os.Getenv("LOCALAPPDATA"); local != "" {
		root = local
	}
	root = filepath.Join(root, "JortanBridge")
	os.MkdirAll(root, 0700)
	binary := filepath.Join(base, "ffmpeg.exe")
	if _, e = os.Stat(binary); e != nil {
		if path, e := exec.LookPath("ffmpeg"); e == nil {
			binary = path
		} else {
			fmt.Println("Extraia o pacote completo: ffmpeg.exe está ausente.")
			return
		}
	}
	listener, e := net.Listen("tcp4", net.JoinHostPort("127.0.0.1", itoa(*port)))
	if e != nil {
		fmt.Println("A ponte já está aberta ou a porta está ocupada.")
		return
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	b := newBridge(filepath.Join(root, "config.bin"), binary, root)
	defer b.close()
	b.startIdle(ctx)
	go b.runAlerts(ctx)
	keepAwake(ctx)
	server := &http.Server{Handler: b.handler(), ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	go func() {
		if e := server.Serve(listener); e != http.ErrServerClosed {
			cancel()
		}
	}()
	setup := "http://" + listener.Addr().String() + "/setup#" + b.setupNonce
	fmt.Println("NINHO MONITOR 1.5.1 — WINDOWS\nMantenha esta janela aberta e a tampa do notebook aberta.\nConfigure a câmera na página local que será aberta:")
	fmt.Println(setup)
	openBrowser(setup)
	if !*local {
		if *fixed {
			b.mu.Lock()
			b.remoteMode = "fixo_tailscale"
			b.mu.Unlock()
			go startFixedTunnel(ctx, b)
		} else {
			go startTunnel(ctx, b, base, "http://"+listener.Addr().String())
		}
	}
	<-ctx.Done()
	shutdown, end := context.WithTimeout(context.Background(), 5*time.Second)
	defer end()
	server.Shutdown(shutdown)
}

var publicAddress = regexp.MustCompile(`https://[a-z0-9-]+\.trycloudflare\.com`)

func startTunnel(ctx context.Context, b *bridge, base, origin string) {
	binary := filepath.Join(base, "cloudflared.exe")
	if _, e := os.Stat(binary); e != nil {
		fmt.Println("cloudflared.exe ausente. Extraia o pacote completo.")
		return
	}
	cmd := exec.CommandContext(ctx, binary, "tunnel", "--no-autoupdate", "--protocol", "http2", "--url", origin)
	stderr, e := cmd.StderrPipe()
	if e != nil {
		return
	}
	cmd.Stdout = io.Discard
	if e = cmd.Start(); e != nil {
		fmt.Println("Não foi possível iniciar o endereço remoto.")
		return
	}
	if e = attachProcess(cmd); e != nil {
		cmd.Process.Kill()
		cmd.Wait()
		fmt.Println("Não foi possível proteger o processo do túnel.")
		return
	}
	scanner := bufio.NewScanner(stderr)
	for scanner.Scan() {
		line := scanner.Text()
		if link := publicAddress.FindString(line); link != "" {
			b.mu.Lock()
			changed := b.publicURL != link
			b.publicURL = link
			b.mu.Unlock()
			if changed {
				fmt.Println("\nENDEREÇO REMOTO: " + link + "\nUse a senha de acesso remoto criada no painel local.\nO endereço pode mudar ao reiniciar a ponte.")
			}
		}
	}
	cmd.Wait()
	b.mu.Lock()
	b.publicURL = ""
	b.mu.Unlock()
	if ctx.Err() == nil {
		fmt.Println("Túnel encerrado. Feche e abra novamente a ponte para reconectar.")
	}
}

var _ = strings.TrimSpace
