package main

import (
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"time"
)

// The notebook owns all schedules. No browser timer is needed for automations.
type homeProfile struct {
	Enabled     bool   `json:"enabled"`
	Sensitivity string `json:"sensitivity"`
	Notify      bool   `json:"notifications"`
	Cooldown    int    `json:"cooldownSeconds"`
}
type homeSchedule struct {
	ID      string `json:"id"`
	At      string `json:"at"`
	Mode    string `json:"mode"`
	Enabled bool   `json:"enabled"`
}
type homeEvent struct {
	ID    uint64    `json:"id"`
	At    time.Time `json:"at"`
	Kind  string    `json:"kind"`
	Code  string    `json:"code"`
	Level string    `json:"level"`
	Mode  string    `json:"mode"`
}
type powerReading struct {
	Known      bool
	AC         int // 0 battery, 1 mains, -1 unknown
	HasBattery bool
	Percent    int // -1 unavailable
	Charging   bool
	DiskKnown  bool
	DiskFree   uint64
}
type healthItem struct {
	Code  string `json:"code"`
	Level string `json:"level"`
}
type homeHealth struct {
	CheckedAt time.Time    `json:"checkedAt"`
	Level     string       `json:"level"`
	Items     []healthItem `json:"items"`
	Battery   *int         `json:"batteryPercent,omitempty"`
}

func validMode(mode string) bool { return mode == "casa" || mode == "fora" || mode == "dormir" }
func cloneProfiles(in map[string]homeProfile) map[string]homeProfile {
	out := map[string]homeProfile{}
	for k, v := range in {
		out[k] = v
	}
	return out
}
func (a *alertManager) initHomeLocked() {
	if a.cfg.Version < 2 || !validMode(a.cfg.Mode) || len(a.cfg.Profiles) != 3 {
		a.cfg.Version = 2
		a.cfg.Mode = "casa"
		a.cfg.HealthNotices = true
		a.cfg.Profiles = map[string]homeProfile{
			"casa":   {a.cfg.Enabled, a.cfg.Sensitivity, true, 60},
			"fora":   {true, "normal", true, 60},
			"dormir": {true, "high", true, 15},
		}
	}
	a.healthStates = map[string]string{}
	a.health = homeHealth{Level: "unknown", Items: []healthItem{{"health_pending", "unknown"}}}
	a.monitorSince = time.Now()
}
func pruneHistory(in []homeEvent, now time.Time) []homeEvent {
	out := make([]homeEvent, 0, len(in))
	for _, e := range in {
		if !e.At.Before(now.Add(-7 * 24 * time.Hour)) {
			out = append(out, e)
		}
	}
	if len(out) > 300 {
		out = out[len(out)-300:]
	}
	return out
}

// Only fixed event codes and timestamps are retained, never media or credentials.
func (a *alertManager) recordLocked(kind, code, level string, now time.Time) {
	next := a.cfg
	next.NextEvent++
	next.History = append(pruneHistory(next.History, now), homeEvent{next.NextEvent, now, kind, code, level, next.Mode})
	next.History = pruneHistory(next.History, now)
	if a.saveLocked(next) != nil {
		// Preserve the event in memory and show that disk persistence needs attention.
		a.cfg = next
		a.code = "historico_nao_salvo"
	}
}
func (a *alertManager) homeStatus(now time.Time) map[string]any {
	a.mu.Lock()
	defer a.mu.Unlock()
	history := pruneHistory(a.cfg.History, now)
	out := make([]homeEvent, len(history))
	for i := range history {
		out[len(history)-1-i] = history[i]
	}
	_, offset := now.Zone()
	sign := "+"
	if offset < 0 {
		sign = "-"
		offset = -offset
	}
	return map[string]any{"mode": a.cfg.Mode, "profiles": cloneProfiles(a.cfg.Profiles), "schedules": a.cfg.Schedules, "healthNotifications": a.cfg.HealthNotices, "health": a.health, "history": out, "notebookTime": now.Format("15:04"), "notebookZone": fmt.Sprintf("UTC%s%02d:%02d", sign, offset/3600, offset%3600/60), "error": a.code}
}
func (a *alertManager) applyModeLocked(mode, code string, now time.Time) error {
	if !validMode(mode) {
		return errors.New("modo_invalido")
	}
	next := a.cfg
	next.Mode = mode
	profile := next.Profiles[mode]
	next.Enabled = profile.Enabled
	next.Sensitivity = profile.Sensitivity
	if a.saveLocked(next) != nil {
		return errors.New("nao_foi_possivel_salvar_modo")
	}
	a.generation++
	a.detector.reset()
	a.monitorSince = now
	a.recordLocked("mode", code, "info", now)
	return nil
}
func (a *alertManager) setMode(mode string, now time.Time) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.applyModeLocked(mode, "mode_manual", now)
}
func (a *alertManager) setProfile(mode string, p homeProfile, now time.Time) error {
	if !validMode(mode) || !validSensitivity(p.Sensitivity) || (p.Cooldown != 15 && p.Cooldown != 30 && p.Cooldown != 60 && p.Cooldown != 120) {
		return errors.New("ajustes_do_modo_invalidos")
	}
	a.mu.Lock()
	defer a.mu.Unlock()
	next := a.cfg
	next.Profiles = cloneProfiles(next.Profiles)
	next.Profiles[mode] = p
	if next.Mode == mode {
		next.Enabled = p.Enabled
		next.Sensitivity = p.Sensitivity
	}
	if a.saveLocked(next) != nil {
		return errors.New("nao_foi_possivel_salvar_modo")
	}
	a.generation++
	a.detector.reset()
	a.monitorSince = now
	a.recordLocked("settings", "profile_updated", "info", now)
	return nil
}
func validClock(s string) bool {
	if len(s) != 5 || s[2] != ':' {
		return false
	}
	for _, i := range []int{0, 1, 3, 4} {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	h, e := strconv.Atoi(s[:2])
	m, f := strconv.Atoi(s[3:])
	return e == nil && f == nil && h >= 0 && h < 24 && m >= 0 && m < 60
}
func (a *alertManager) setSchedules(rules []homeSchedule, now time.Time) error {
	if len(rules) > 8 {
		return errors.New("limite_de_oito_rotinas")
	}
	seen := map[string]bool{}
	ids := map[string]bool{}
	nextRules := append([]homeSchedule(nil), rules...)
	for i := range nextRules {
		r := &nextRules[i]
		if !validMode(r.Mode) || !validClock(r.At) || (r.Enabled && seen[r.At]) {
			return errors.New("horario_ou_modo_invalido")
		}
		if r.Enabled {
			seen[r.At] = true
		}
		if r.ID == "" {
			r.ID = randomID()
		}
		if len(r.ID) > 64 || ids[r.ID] {
			return errors.New("rotina_invalida")
		}
		ids[r.ID] = true
	}
	sort.Slice(nextRules, func(i, j int) bool { return nextRules[i].At < nextRules[j].At })
	a.mu.Lock()
	defer a.mu.Unlock()
	next := a.cfg
	next.Schedules = nextRules
	if a.saveLocked(next) != nil {
		return errors.New("nao_foi_possivel_salvar_rotinas")
	}
	a.recordLocked("automation", "schedule_updated", "info", now)
	return nil
}
func (a *alertManager) tickSchedule(now time.Time) {
	a.mu.Lock()
	defer a.mu.Unlock()
	// Only run a matching current minute, not missed schedules from before startup.
	for _, r := range a.cfg.Schedules {
		if !r.Enabled || r.At != now.Format("15:04") {
			continue
		}
		key := now.Format("2006-01-02 15:04") + "/" + r.ID
		if a.cfg.LastSchedule == key {
			return
		}
		next := a.cfg
		next.LastSchedule = key
		if a.saveLocked(next) != nil {
			a.code = "rotina_nao_salva"
			return
		}
		if a.cfg.Mode != r.Mode {
			if a.applyModeLocked(r.Mode, "mode_scheduled", now) != nil {
				a.code = "rotina_nao_aplicada"
			}
		}
		return
	}
}
func (a *alertManager) setHealthNotices(enabled bool) error {
	a.mu.Lock()
	defer a.mu.Unlock()
	next := a.cfg
	next.HealthNotices = enabled
	if a.saveLocked(next) != nil {
		return errors.New("nao_foi_possivel_salvar_alertas")
	}
	a.recordLocked("settings", "health_alerts_updated", "info", time.Now())
	return nil
}
func (a *alertManager) clearHistory() error {
	a.mu.Lock()
	defer a.mu.Unlock()
	next := a.cfg
	next.History = nil
	if a.saveLocked(next) != nil {
		return errors.New("historico_nao_apagado")
	}
	a.latest = alertEvent{}
	return nil
}
func (a *alertManager) homeAPI(w http.ResponseWriter, r *http.Request, b *bridge) {
	read := r.URL.Path == "/api/home"
	if (read && r.Method != "GET") || (!read && r.Method != "POST") {
		fail(w, 405, "metodo_recusado")
		return
	}
	if _, ok := b.authorize(w, r, !read); !ok {
		return
	}
	var e error
	switch r.URL.Path {
	case "/api/home":
	case "/api/home/mode":
		var in struct {
			Mode string `json:"mode"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		e = a.setMode(in.Mode, time.Now())
	case "/api/home/profile":
		var in struct {
			Mode    string      `json:"mode"`
			Profile homeProfile `json:"profile"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		e = a.setProfile(in.Mode, in.Profile, time.Now())
	case "/api/home/schedules":
		var in struct {
			Schedules []homeSchedule `json:"schedules"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		e = a.setSchedules(in.Schedules, time.Now())
	case "/api/home/health":
		var in struct {
			Enabled bool `json:"enabled"`
		}
		if !decodeJSON(w, r, &in) {
			return
		}
		e = a.setHealthNotices(in.Enabled)
	case "/api/home/history/clear":
		var in struct{}
		if !decodeJSON(w, r, &in) {
			return
		}
		e = a.clearHistory()
	default:
		fail(w, 404, "nao_encontrado")
		return
	}
	if e != nil {
		fail(w, 400, e.Error())
		return
	}
	jsonReply(w, 200, a.homeStatus(time.Now()))
}
