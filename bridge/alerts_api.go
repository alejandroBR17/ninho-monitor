package main

import (
	"context"
	webpush "github.com/SherClockHolmes/webpush-go"
	"net/http"
	"time"
)

func (b *bridge) alertAPI(w http.ResponseWriter, r *http.Request) {
	read := r.URL.Path == "/api/alerts"
	if (read && r.Method != "GET") || (!read && r.Method != "POST") {
		fail(w, 405, "metodo_recusado")
		return
	}
	if _, ok := b.authorize(w, r, !read); !ok {
		return
	}
	switch r.URL.Path {
	case "/api/alerts":
		jsonReply(w, 200, b.alerts.status())
	case "/api/alerts/settings":
		var in struct {
			Enabled     bool   `json:"enabled"`
			Sensitivity string `json:"sensitivity"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		if e := b.alerts.settings(in.Enabled, in.Sensitivity); e != nil {
			fail(w, 400, e.Error())
			return
		}
		jsonReply(w, 200, b.alerts.status())
	case "/api/alerts/key":
		key, e := b.alerts.key()
		if e != nil {
			fail(w, 500, e.Error())
			return
		}
		jsonReply(w, 200, map[string]string{"publicKey": key})
	case "/api/alerts/subscribe":
		var in struct {
			Endpoint       string       `json:"endpoint"`
			Keys           webpush.Keys `json:"keys"`
			ExpirationTime *float64     `json:"expirationTime"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		if e := b.alerts.subscribe(webpush.Subscription{Endpoint: in.Endpoint, Keys: in.Keys}); e != nil {
			fail(w, 400, e.Error())
			return
		}
		jsonReply(w, 200, map[string]bool{"subscribed": true})
	case "/api/alerts/unsubscribe":
		var in struct {
			Endpoint string `json:"endpoint"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		if b.alerts.unsubscribe(in.Endpoint) != nil {
			fail(w, 500, "nao_foi_possivel_salvar_alertas")
			return
		}
		jsonReply(w, 200, map[string]bool{"removed": true})
	case "/api/alerts/test":
		var in struct {
			Endpoint string `json:"endpoint"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		if !b.alerts.test(r.Context(), in.Endpoint) {
			fail(w, 502, "push_nao_confirmado")
			return
		}
		jsonReply(w, 200, map[string]bool{"accepted": true})
	}
}
func (b *bridge) runAlerts(ctx context.Context) {
	go b.alerts.run(ctx)
	timer := time.NewTicker(5 * time.Second)
	defer timer.Stop()
	next := time.Time{}
	nextHealth := time.Time{}
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-timer.C:
			b.alerts.tickSchedule(now)
			if !now.Before(nextHealth) {
				b.alerts.updateHealth(readNotebookHealth(b.root), now)
				nextHealth = now.Add(15 * time.Second)
			}
			if !b.alerts.enabled() {
				next = time.Time{}
				continue
			}
			b.operations.RLock()
			b.mu.Lock()
			configured := b.configured
			b.mu.Unlock()
			if configured && b.alerts.enabled() {
				b.stream.mu.Lock()
				running := b.stream.cmd != nil || b.stream.starting
				started := b.stream.started
				b.stream.mu.Unlock()
				b.alerts.mu.Lock()
				last := b.alerts.lastFrame
				b.alerts.mu.Unlock()
				if running && now.Sub(started) > 35*time.Second && (last.IsZero() || now.Sub(last) > 35*time.Second) {
					b.stream.stop()
					running = false
				}
				if !running && !now.Before(next) {
					_ = b.stream.start()
					next = now.Add(30 * time.Second)
				}
			}
			b.operations.RUnlock()
		}
	}
}
