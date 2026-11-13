package main

import (
	"context"
	"crypto/subtle"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"time"
)

//go:embed web/* web/vendor/*
var assets embed.FS

type loginSession struct {
	CSRF  string
	Until time.Time
}
type rate struct {
	Count int
	Until time.Time
}
type bridge struct {
	operations                                   sync.RWMutex
	mu                                           sync.Mutex
	cfg                                          Config
	configured                                   bool
	configFile, setupNonce, publicURL            string
	remoteMode, tunnelState, tunnelAuthorization string
	sessions                                     map[string]loginSession
	rates                                        map[string]rate
	stream                                       *streamManager
	motion                                       *motion
	root                                         string
	alerts                                       *alertManager
}

func newBridge(configFile, binary, root string) *bridge {
	b := &bridge{configFile: configFile, setupNonce: randomID(), sessions: map[string]loginSession{}, rates: map[string]rate{}, root: root}
	c, e := loadConfig(configFile)
	if e == nil {
		b.cfg = c
		b.configured = true
	}
	b.alerts = newAlerts(filepath.Join(root, "alerts.bin"), c)
	b.stream = &streamManager{cfg: c, binary: binary, dir: filepath.Join(root, "hls"), alerts: b.alerts}
	b.motion = newMotion()
	os.RemoveAll(b.stream.dir)
	return b
}
func jsonReply(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}
func fail(w http.ResponseWriter, status int, code string) {
	jsonReply(w, status, map[string]string{"erro": code})
}
func localHost(r *http.Request) bool {
	host, _, e := net.SplitHostPort(r.Host)
	if e != nil {
		host = r.Host
	}
	return host == "127.0.0.1" || host == "localhost" || host == "[::1]" || host == "::1"
}
func sameOrigin(r *http.Request) bool {
	o := r.Header.Get("Origin")
	if o == "" {
		return false
	}
	scheme := "https"
	if localHost(r) && r.TLS == nil {
		scheme = "http"
	}
	return o == scheme+"://"+r.Host
}
func decodeJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
		fail(w, 415, "formato_recusado")
		return false
	}
	d := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192))
	d.DisallowUnknownFields()
	if e := d.Decode(v); e != nil {
		fail(w, 400, "pedido_invalido")
		return false
	}
	return true
}
func (b *bridge) session(r *http.Request) (string, loginSession, bool) {
	cookie, e := r.Cookie("jortan_session")
	if e != nil {
		return "", loginSession{}, false
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	s, ok := b.sessions[cookie.Value]
	if !ok || time.Now().After(s.Until) {
		delete(b.sessions, cookie.Value)
		return "", s, false
	}
	return cookie.Value, s, true
}
func (b *bridge) authorize(w http.ResponseWriter, r *http.Request, post bool) (string, bool) {
	id, s, ok := b.session(r)
	if !ok {
		fail(w, 401, "entre_com_sua_senha")
		return "", false
	}
	if post && (!sameOrigin(r) || subtle.ConstantTimeCompare([]byte(r.Header.Get("X-CSRF")), []byte(s.CSRF)) != 1) {
		fail(w, 403, "origem_recusada")
		return "", false
	}
	return id, true
}
func (b *bridge) handler() http.Handler {
	sub, _ := fs.Sub(assets, "web")
	static := http.FileServer(http.FS(sub))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/api/setup" {
			b.operations.RLock()
			defer b.operations.RUnlock()
		}
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; media-src 'self' blob:; connect-src 'self'; worker-src 'self' blob:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'")
		if r.Method != "GET" && r.Method != "POST" {
			fail(w, 405, "metodo_recusado")
			return
		}
		switch r.URL.Path {
		case "/favicon.ico":
			r.URL.Path = "/icon180.png"
			static.ServeHTTP(w, r)
		case "/setup":
			if !localHost(r) {
				http.NotFound(w, r)
				return
			}
			r.URL.Path = "/setup.html"
			static.ServeHTTP(w, r)
		case "/setup.html", "/setup.js":
			if !localHost(r) {
				http.NotFound(w, r)
				return
			}
			static.ServeHTTP(w, r)
		case "/api/setup":
			b.setup(w, r)
		case "/api/local-status":
			if !localHost(r) || r.Header.Get("X-Setup") != b.setupNonce {
				fail(w, 403, "painel_local_apenas")
				return
			}
			b.mu.Lock()
			out := map[string]any{"configurada": b.configured, "endereco": b.publicURL, "modoEndereco": b.remoteMode, "estadoEndereco": b.tunnelState, "autorizarEndereco": b.tunnelAuthorization}
			b.mu.Unlock()
			jsonReply(w, 200, out)
		case "/api/home", "/api/home/mode", "/api/home/profile", "/api/home/schedules", "/api/home/health", "/api/home/history/clear":
			b.alerts.homeAPI(w, r, b)
		case "/api/alerts", "/api/alerts/settings", "/api/alerts/key", "/api/alerts/subscribe", "/api/alerts/unsubscribe", "/api/alerts/test":
			b.alertAPI(w, r)
		case "/api/login":
			b.login(w, r)
		case "/api/session":
			_, s, ok := b.session(r)
			if !ok {
				b.mu.Lock()
				configured := b.configured
				b.mu.Unlock()
				jsonReply(w, 200, map[string]any{"authenticated": false, "configured": configured})
				return
			}
			jsonReply(w, 200, map[string]any{"authenticated": true, "csrf": s.CSRF})
		case "/api/logout":
			if r.Method != "POST" {
				fail(w, 405, "metodo_recusado")
				return
			}
			id, ok := b.authorize(w, r, true)
			if !ok {
				return
			}
			b.mu.Lock()
			delete(b.sessions, id)
			b.mu.Unlock()
			b.motion.release(id)
			http.SetCookie(w, &http.Cookie{Name: "jortan_session", Value: "", Path: "/", MaxAge: -1, Secure: !localHost(r) || r.TLS != nil, HttpOnly: true, SameSite: http.SameSiteStrictMode})
			jsonReply(w, 200, map[string]bool{"ok": true})
		case "/api/play":
			if r.Method != "POST" {
				fail(w, 405, "metodo_recusado")
				return
			}
			if _, ok := b.authorize(w, r, true); !ok {
				return
			}
			if e := b.stream.start(); e != nil {
				fail(w, 503, "nao_foi_possivel_iniciar_video")
				return
			}
			jsonReply(w, 202, map[string]bool{"iniciando": true})
		case "/api/viewer-heartbeat":
			if r.Method != "POST" {
				fail(w, 405, "metodo_recusado")
				return
			}
			if _, ok := b.authorize(w, r, true); !ok {
				return
			}
			b.stream.touch()
			jsonReply(w, 200, map[string]bool{"ok": true})
		case "/api/status":
			if _, ok := b.authorize(w, r, false); !ok {
				return
			}
			video, err := b.stream.status()
			ready, ptzErr := b.motion.status()
			jsonReply(w, 200, map[string]any{"videoDisponivel": video, "erroVideo": err, "controlePronto": ready, "erroControle": ptzErr, "atrasoMedido": false, "ponteVersao": "1.4.0", "diagnosticoVideo": b.stream.diagnostic()})
		case "/api/prepare":
			if r.Method != "POST" {
				fail(w, 405, "metodo_recusado")
				return
			}
			if _, ok := b.authorize(w, r, true); !ok {
				return
			}
			b.mu.Lock()
			c := b.cfg
			b.mu.Unlock()
			if e := b.motion.prepare(c); e != nil {
				fail(w, 502, e.Error())
				return
			}
			jsonReply(w, 200, map[string]bool{"paradaConfirmada": true, "movimentoFisicoVerificado": false})
		case "/api/ptz":
			if r.Method != "POST" {
				fail(w, 405, "metodo_recusado")
				return
			}
			id, ok := b.authorize(w, r, true)
			if !ok {
				return
			}
			var i motionIntent
			if !decodeJSON(w, r, &i) {
				return
			}
			if e := b.motion.submit(id, i); e != nil {
				fail(w, 409, e.Error())
				return
			}
			b.alerts.suppress()
			jsonReply(w, 202, map[string]bool{"solicitado": true})
		default:
			if strings.HasPrefix(r.URL.Path, "/hls/") {
				if _, ok := b.authorize(w, r, false); !ok {
					return
				}
				name := strings.TrimPrefix(r.URL.Path, "/hls/")
				if !hlsName.MatchString(name) {
					http.NotFound(w, r)
					return
				}
				b.stream.touch()
				if strings.HasSuffix(name, ".m3u8") {
					w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
				} else {
					w.Header().Set("Content-Type", "video/mp2t")
				}
				http.ServeFile(w, r, filepath.Join(b.stream.dir, name))
				return
			}
			switch r.URL.Path {
			case "/", "/index.html", "/app.js", "/viewer-layout.js", "/alerts.js", "/home.js", "/style.css", "/manifest.webmanifest", "/sw.js", "/icon.svg", "/icon180.png", "/vendor/hls.min.js", "/vendor/HLS-LICENSE.txt":
				static.ServeHTTP(w, r)
			default:
				http.NotFound(w, r)
			}
		}
	})
}

var hlsName = regexp.MustCompile(`^(live\.m3u8|segment-[0-9]{9}\.ts)$`)

func (b *bridge) setup(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" || !localHost(r) || !sameOrigin(r) || subtle.ConstantTimeCompare([]byte(r.Header.Get("X-Setup")), []byte(b.setupNonce)) != 1 {
		fail(w, 403, "painel_local_apenas")
		return
	}
	b.operations.Lock()
	defer b.operations.Unlock()
	var in struct {
		Host           string `json:"host"`
		Port           int    `json:"port"`
		Path           string `json:"path"`
		User           string `json:"user"`
		Password       string `json:"password"`
		OnvifPort      int    `json:"onvifPort"`
		RemotePassword string `json:"remotePassword"`
	}
	if !decodeJSON(w, r, &in) {
		return
	}
	c := Config{Host: strings.TrimSpace(in.Host), Port: in.Port, Path: strings.TrimSpace(in.Path), User: in.User, Password: in.Password, OnvifPort: in.OnvifPort}
	if e := configurePassword(&c, in.RemotePassword); e != nil {
		fail(w, 400, e.Error())
		return
	}
	if !c.valid() {
		fail(w, 400, "confira_ip_portas_caminho")
		return
	}
	if e := saveConfig(b.configFile, c); e != nil {
		fail(w, 500, "nao_foi_possivel_salvar_protegido")
		return
	}
	b.motion.close()
	b.stream.stop()
	b.mu.Lock()
	b.cfg = c
	b.configured = true
	b.sessions = map[string]loginSession{}
	b.mu.Unlock()
	b.stream.mu.Lock()
	b.stream.cfg = c
	b.stream.mu.Unlock()
	b.motion = newMotion()
	b.alerts.bind(c)
	jsonReply(w, 200, map[string]bool{"salvo": true})
}
func (b *bridge) login(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" || !sameOrigin(r) {
		fail(w, 403, "origem_recusada")
		return
	}
	var in struct {
		Password string `json:"password"`
	}
	if !decodeJSON(w, r, &in) {
		return
	}
	host, _, _ := net.SplitHostPort(r.RemoteAddr)
	if !localHost(r) && r.Header.Get("CF-Connecting-IP") != "" {
		host = r.Header.Get("CF-Connecting-IP")
	}
	b.mu.Lock()
	c, configured := b.cfg, b.configured
	now := time.Now()
	for k, v := range b.rates {
		if now.After(v.Until) {
			delete(b.rates, k)
		}
	}
	limit := b.rates[host]
	if len(b.rates) > 2048 || limit.Count >= 5 && now.Before(limit.Until) {
		b.mu.Unlock()
		w.Header().Set("Retry-After", "900")
		fail(w, 429, "aguarde_antes_de_tentar")
		return
	}
	if now.After(limit.Until) {
		limit = rate{Until: now.Add(15 * time.Minute)}
	}
	limit.Count++
	b.rates[host] = limit
	b.mu.Unlock()
	valid := configured && len(in.Password) <= 256 && subtle.ConstantTimeCompare([]byte(passwordHash(in.Password, c.Salt)), []byte(c.Hash)) == 1
	if !valid {
		fail(w, 401, "senha_incorreta_ou_ponte_nao_configurada")
		return
	}
	id := randomID()
	s := loginSession{CSRF: randomID(), Until: now.Add(12 * time.Hour)}
	b.mu.Lock()
	for k, v := range b.sessions {
		if now.After(v.Until) {
			delete(b.sessions, k)
		}
	}
	if len(b.sessions) >= 20 {
		b.mu.Unlock()
		fail(w, 429, "limite_de_sessoes")
		return
	}
	delete(b.rates, host)
	b.sessions[id] = s
	b.mu.Unlock()
	http.SetCookie(w, &http.Cookie{Name: "jortan_session", Value: id, Path: "/", Secure: !localHost(r) || r.TLS != nil, HttpOnly: true, SameSite: http.SameSiteStrictMode, MaxAge: 12 * 3600})
	jsonReply(w, 200, map[string]string{"csrf": s.CSRF})
}
func (b *bridge) close()                        { b.motion.close(); b.stream.stop(); os.RemoveAll(b.stream.dir) }
func (b *bridge) startIdle(ctx context.Context) { go b.stream.idleLoop(ctx) }

var _ = fmt.Sprint
var _ = io.Discard
