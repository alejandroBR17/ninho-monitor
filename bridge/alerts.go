package main

import (
	"context"
	"crypto/ecdh"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	webpush "github.com/SherClockHolmes/webpush-go"
)

const frameWidth = 160
const frameHeight = 90
const frameSize = frameWidth * frameHeight

type alertConfig struct {
	Owner         string                 `json:"owner"`
	Enabled       bool                   `json:"enabled"`
	Sensitivity   string                 `json:"sensitivity"`
	PrivateKey    string                 `json:"privateKey"`
	PublicKey     string                 `json:"publicKey"`
	Subscriptions []webpush.Subscription `json:"subscriptions"`
	Version       int                    `json:"version,omitempty"`
	Mode          string                 `json:"mode,omitempty"`
	Profiles      map[string]homeProfile `json:"profiles,omitempty"`
	HealthNotices bool                   `json:"healthNotices"`
	Schedules     []homeSchedule         `json:"schedules,omitempty"`
	LastSchedule  string                 `json:"lastSchedule,omitempty"`
	History       []homeEvent            `json:"history,omitempty"`
	NextEvent     uint64                 `json:"nextEvent,omitempty"`
}
type alertEvent struct {
	Generation uint64    `json:"-"`
	ID         uint64    `json:"id"`
	At         time.Time `json:"horario"`
	Test       bool      `json:"teste,omitempty"`
	Kind       string    `json:"kind,omitempty"`
	Code       string    `json:"code,omitempty"`
}
type imageDetector struct {
	previous              []byte
	warmup, streak        int
	mutedUntil, lastEvent time.Time
	cooldown              time.Duration
}

func (d *imageDetector) reset() { d.previous = nil; d.warmup = 0; d.streak = 0 }
func (d *imageDetector) frame(data []byte, now time.Time, sensitivity string) bool {
	if len(data) != frameSize {
		return false
	}
	if len(d.previous) != frameSize {
		d.previous = append([]byte(nil), data...)
		d.warmup = 1
		return false
	}
	sum := 0
	for i, v := range data {
		sum += int(v) - int(d.previous[i])
	}
	shift := sum / frameSize
	changed := 0
	blocks := [144]int{}
	for i, v := range data {
		delta := int(v) - int(d.previous[i]) - shift
		if delta < 0 {
			delta = -delta
		}
		if delta >= 22 {
			changed++
			x, y := i%frameWidth, i/frameWidth
			blocks[(y/10)*16+x/10]++
		}
	}
	copy(d.previous, data)
	d.warmup++
	if d.warmup < 6 || now.Before(d.mutedUntil) {
		d.streak = 0
		return false
	}
	hot := 0
	for _, v := range blocks {
		if v >= 25 {
			hot++
		}
	}
	minimum := frameSize * 5 / 100
	if sensitivity == "high" {
		minimum = frameSize * 2 / 100
	}
	if sensitivity == "low" {
		minimum = frameSize * 12 / 100
	}
	if changed >= minimum && hot >= 3 {
		d.streak++
	} else {
		d.streak = 0
	}
	cooldown := d.cooldown
	if cooldown == 0 {
		cooldown = time.Minute
	}
	if d.streak >= 3 && now.Sub(d.lastEvent) >= cooldown {
		d.lastEvent = now
		d.streak = 0
		return true
	}
	return false
}

type alertManager struct {
	mu           sync.Mutex
	path         string
	cfg          alertConfig
	detector     imageDetector
	latest       alertEvent
	lastFrame    time.Time
	code         string
	generation   uint64
	events       chan alertEvent
	client       webpush.HTTPClient
	health       homeHealth
	monitorSince time.Time
	healthStates map[string]string
}

func alertOwner(c Config) string {
	if c.Hash == "" {
		return ""
	}
	h := sha256.Sum256([]byte(c.Salt + c.Hash))
	return hex.EncodeToString(h[:])
}
func newAlerts(path string, c Config) *alertManager {
	a := &alertManager{path: path, cfg: alertConfig{Owner: alertOwner(c), Sensitivity: "normal"}, events: make(chan alertEvent, 8), client: &http.Client{Timeout: 8 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
	raw, e := os.ReadFile(path)
	if e == nil {
		raw, e = unprotect(raw)
		if e == nil {
			var saved alertConfig
			if json.Unmarshal(raw, &saved) == nil && saved.Owner == a.cfg.Owner && validSensitivity(saved.Sensitivity) {
				a.cfg = saved
			} else {
				a.code = "alertas_redefinidos"
			}
		}
		if e != nil {
			a.code = "configuracao_alertas_indisponivel"
		}
	}
	a.initHomeLocked()
	return a
}
func validSensitivity(s string) bool { return s == "normal" || s == "high" || s == "low" }
func (a *alertManager) saveLocked(next alertConfig) error {
	raw, e := json.Marshal(next)
	if e != nil {
		return e
	}
	raw, e = protect(raw)
	if e != nil {
		return e
	}
	if e = os.MkdirAll(filepath.Dir(a.path), 0700); e != nil {
		return e
	}
	if e = os.WriteFile(a.path+".tmp", raw, 0600); e != nil {
		return e
	}
	if e = replaceFile(a.path+".tmp", a.path); e != nil {
		return e
	}
	a.cfg = next
	return nil
}
func (a *alertManager) bind(c Config) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.generation++
	a.cfg = alertConfig{Owner: alertOwner(c), Sensitivity: "normal"}
	a.initHomeLocked()
	a.detector.reset()
	a.latest = alertEvent{}
	if a.saveLocked(a.cfg) != nil {
		a.code = "configuracao_alertas_indisponivel"
	}
}
func (a *alertManager) enabled() bool { a.mu.Lock(); defer a.mu.Unlock(); return a.cfg.Enabled }
func (a *alertManager) settings(enabled bool, sensitivity string) error {
	if !validSensitivity(sensitivity) {
		return errors.New("sensibilidade_invalida")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	next := a.cfg
	next.Enabled = enabled
	next.Sensitivity = sensitivity
	next.Profiles = cloneProfiles(next.Profiles)
	profile := next.Profiles[next.Mode]
	profile.Enabled = enabled
	profile.Sensitivity = sensitivity
	next.Profiles[next.Mode] = profile
	if a.saveLocked(next) != nil {
		return errors.New("nao_foi_possivel_salvar_alertas")
	}
	a.generation++
	a.detector.reset()
	a.monitorSince = time.Now()
	a.recordLocked("settings", "monitor_updated", "info", time.Now())
	a.code = ""
	return nil
}
func (a *alertManager) key() (string, error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.cfg.PublicKey != "" {
		return a.cfg.PublicKey, nil
	}
	private, public, e := webpush.GenerateVAPIDKeys()
	if e != nil {
		return "", errors.New("chave_push_indisponivel")
	}
	next := a.cfg
	next.PrivateKey = private
	next.PublicKey = public
	if a.saveLocked(next) != nil {
		return "", errors.New("nao_foi_possivel_salvar_alertas")
	}
	return public, nil
}
func validSubscription(s webpush.Subscription) bool {
	u, e := url.Parse(s.Endpoint)
	if e != nil || u.Scheme != "https" || u.User != nil || u.Port() != "" || u.Fragment != "" || u.Path == "" || len(s.Endpoint) > 4096 {
		return false
	}
	host := strings.ToLower(u.Hostname())
	allowed := host == "web.push.apple.com" || host == "fcm.googleapis.com" || host == "updates.push.services.mozilla.com" || strings.HasSuffix(host, ".push.services.mozilla.com")
	if !allowed {
		return false
	}
	auth, e := base64.RawURLEncoding.DecodeString(strings.TrimRight(s.Keys.Auth, "="))
	if e != nil || len(auth) != 16 {
		return false
	}
	public, e := base64.RawURLEncoding.DecodeString(strings.TrimRight(s.Keys.P256dh, "="))
	if e != nil {
		return false
	}
	_, e = ecdh.P256().NewPublicKey(public)
	return e == nil
}
func (a *alertManager) subscribe(s webpush.Subscription) error {
	if !validSubscription(s) {
		return errors.New("assinatura_push_invalida")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.cfg.PrivateKey == "" {
		return errors.New("ative_notificacoes_primeiro")
	}
	next := a.cfg
	next.Subscriptions = append([]webpush.Subscription(nil), a.cfg.Subscriptions...)
	for i, old := range next.Subscriptions {
		if old.Endpoint == s.Endpoint {
			next.Subscriptions[i] = s
			if a.saveLocked(next) != nil {
				return errors.New("nao_foi_possivel_salvar_alertas")
			}
			return nil
		}
	}
	if len(next.Subscriptions) >= 10 {
		return errors.New("limite_de_aparelhos")
	}
	next.Subscriptions = append(next.Subscriptions, s)
	if a.saveLocked(next) != nil {
		return errors.New("nao_foi_possivel_salvar_alertas")
	}
	return nil
}
func (a *alertManager) unsubscribe(endpoint string) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	next := a.cfg
	next.Subscriptions = nil
	for _, s := range a.cfg.Subscriptions {
		if s.Endpoint != endpoint {
			next.Subscriptions = append(next.Subscriptions, s)
		}
	}
	return a.saveLocked(next)
}
func (a *alertManager) suppress() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.detector.mutedUntil = time.Now().Add(10 * time.Second)
	a.detector.reset()
}
func (a *alertManager) resetFrames() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.detector.reset()
	a.lastFrame = time.Time{}
}
func (a *alertManager) frame(data []byte) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.lastFrame = time.Now()
	if !a.cfg.Enabled {
		return
	}
	a.detector.cooldown = time.Duration(a.cfg.Profiles[a.cfg.Mode].Cooldown) * time.Second
	if a.detector.frame(data, a.lastFrame, a.cfg.Sensitivity) {
		a.recordLocked("motion", "motion", "attention", a.lastFrame)
		a.latest = alertEvent{ID: a.cfg.NextEvent, At: a.lastFrame, Generation: a.generation, Kind: "motion", Code: "motion"}
		if !a.cfg.Profiles[a.cfg.Mode].Notify {
			return
		}
		select {
		case a.events <- a.latest:
		default:
		}
	}
}
func (a *alertManager) status() map[string]any {
	a.mu.Lock()
	defer a.mu.Unlock()
	state := "desativado"
	if a.cfg.Enabled {
		state = "aguardando_video"
		if !a.lastFrame.IsZero() && time.Since(a.lastFrame) < 10*time.Second {
			state = "monitorando"
		}
	}
	return map[string]any{"enabled": a.cfg.Enabled, "sensitivity": a.cfg.Sensitivity, "state": state, "lastEvent": a.latest, "subscribers": len(a.cfg.Subscriptions), "error": a.code, "origin": "analise_de_imagem_no_notebook"}
}
func (a *alertManager) deliver(ctx context.Context, s webpush.Subscription, event alertEvent, generation uint64) bool {
	a.mu.Lock()
	if generation != a.generation || (!event.Test && ((event.Kind == "health" && !a.cfg.HealthNotices) || (event.Kind != "health" && (!a.cfg.Enabled || !a.cfg.Profiles[a.cfg.Mode].Notify)))) {
		a.mu.Unlock()
		return false
	}
	private, public := a.cfg.PrivateKey, a.cfg.PublicKey
	a.mu.Unlock()
	if !validSubscription(s) || private == "" {
		return false
	}
	payload, _ := json.Marshal(map[string]any{"title": "Jortan · movimento detectado", "body": "Alteração de imagem detectada pelo notebook.", "test": event.Test, "kind": event.Kind, "code": event.Code, "time": event.At.UTC().Format(time.RFC3339)})
	ctx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()
	topic := "jortan-motion"
	if event.Kind == "health" {
		topic = "jortan-health"
	}
	response, e := webpush.SendNotificationWithContext(ctx, payload, &s, &webpush.Options{HTTPClient: a.client, Subscriber: "https://github.com/alejandroBR17/ninho-monitor", VAPIDPublicKey: public, VAPIDPrivateKey: private, TTL: 60, Urgency: webpush.UrgencyHigh, Topic: topic})
	if e != nil {
		a.mu.Lock()
		a.code = "push_nao_confirmado"
		a.mu.Unlock()
		return false
	}
	defer response.Body.Close()
	io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode == 404 || response.StatusCode == 410 {
		_ = a.unsubscribe(s.Endpoint)
		return false
	}
	success := response.StatusCode >= 200 && response.StatusCode < 300
	a.mu.Lock()
	if success {
		a.code = ""
	} else {
		a.code = "push_nao_confirmado"
	}
	a.mu.Unlock()
	return success
}
func (a *alertManager) run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case event := <-a.events:
			a.mu.Lock()
			subs := append([]webpush.Subscription(nil), a.cfg.Subscriptions...)
			g := event.Generation
			a.mu.Unlock()
			for _, s := range subs {
				if time.Since(event.At) > 30*time.Second {
					break
				}
				a.deliver(ctx, s, event, g)
			}
		}
	}
}
func (a *alertManager) test(ctx context.Context, endpoint string) bool {
	a.mu.Lock()
	g := a.generation
	var selected *webpush.Subscription
	for _, s := range a.cfg.Subscriptions {
		if s.Endpoint == endpoint {
			copy := s
			selected = &copy
			break
		}
	}
	a.mu.Unlock()
	if selected == nil {
		return false
	}
	return a.deliver(ctx, *selected, alertEvent{At: time.Now(), Test: true}, g)
}

// Raw grayscale is transient memory only; no snapshots or recordings are saved.
type frameSink struct {
	buffer []byte
	frame  func([]byte)
}

func (w *frameSink) Write(p []byte) (int, error) {
	n := len(p)
	for len(p) > 0 {
		take := frameSize - len(w.buffer)
		if take > len(p) {
			take = len(p)
		}
		w.buffer = append(w.buffer, p[:take]...)
		p = p[take:]
		if len(w.buffer) == frameSize {
			w.frame(w.buffer)
			w.buffer = w.buffer[:0]
		}
	}
	return n, nil
}
