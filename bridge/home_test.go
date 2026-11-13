package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestHomeMigrationModesAndPrivateHistory(t *testing.T) {
	path := filepath.Join(t.TempDir(), "alerts.bin")
	c := Config{Salt: "fixture", Hash: "owner"}
	old := alertConfig{Owner: alertOwner(c), Enabled: true, Sensitivity: "low"}
	raw, _ := json.Marshal(old)
	protected, _ := protect(raw)
	if os.WriteFile(path, protected, 0600) != nil {
		t.Fatal("fixture")
	}
	a := newAlerts(path, c)
	if a.cfg.Mode != "casa" || !a.enabled() || a.cfg.Profiles["casa"].Sensitivity != "low" {
		t.Fatal("migration lost existing preferences")
	}
	now := time.Now()
	if a.setMode("dormir", now) != nil {
		t.Fatal("mode")
	}
	if !a.enabled() || a.cfg.Sensitivity != "high" || a.cfg.Profiles["dormir"].Cooldown != 15 {
		t.Fatal("sleep defaults")
	}
	p := a.cfg.Profiles["casa"]
	p.Enabled = false
	p.Notify = false
	if a.setProfile("casa", p, now) != nil || !a.enabled() {
		t.Fatal("inactive profile changed current mode")
	}
	if a.setMode("casa", now) != nil || a.enabled() {
		t.Fatal("home mode did not stop analysis")
	}
	reloaded := newAlerts(path, c)
	if reloaded.cfg.Mode != "casa" || len(reloaded.cfg.History) < 3 || reloaded.cfg.Profiles["dormir"].Cooldown != 15 {
		t.Fatal("home persistence")
	}
	for i := 0; i < 310; i++ {
		a.mu.Lock()
		a.recordLocked("motion", "motion", "attention", now)
		a.mu.Unlock()
	}
	if len(a.cfg.History) != 300 {
		t.Fatal("history not bounded")
	}
	a.cfg.History[0].At = now.Add(-8 * 24 * time.Hour)
	if len(pruneHistory(a.cfg.History, now)) != 299 {
		t.Fatal("retention")
	}
	a.bind(Config{Salt: "other", Hash: "other"})
	if a.enabled() || len(a.cfg.History) != 0 || a.cfg.Mode != "casa" {
		t.Fatal("configuration reset retained private history")
	}
}
func TestDailyAutomationsTimeValidationAndRestart(t *testing.T) {
	a := newAlerts(filepath.Join(t.TempDir(), "alerts.bin"), Config{})
	now := time.Date(2026, 11, 13, 20, 30, 0, 0, time.FixedZone("notebook", -3*3600))
	for _, clock := range []string{"24:00", "20:60", "8:00", "+1:20", "-0:20", "ab:cd"} {
		if validClock(clock) {
			t.Fatal("invalid clock", clock)
		}
	}
	rules := []homeSchedule{{ID: "sleep", At: "20:30", Mode: "dormir", Enabled: true}}
	if a.setSchedules(rules, now) != nil {
		t.Fatal("schedule save")
	}
	a.tickSchedule(now.Add(-time.Minute))
	if a.cfg.Mode != "casa" {
		t.Fatal("fired early")
	}
	a.tickSchedule(now)
	if a.cfg.Mode != "dormir" {
		t.Fatal("did not fire")
	}
	count := len(a.cfg.History)
	a.tickSchedule(now.Add(5 * time.Second))
	if len(a.cfg.History) != count {
		t.Fatal("repeated schedule")
	}
	a.setMode("casa", now)
	reloaded := newAlerts(a.path, Config{})
	reloaded.tickSchedule(now.Add(15 * time.Second))
	if reloaded.cfg.Mode != "casa" {
		t.Fatal("restart repeated completed schedule")
	}
	reloaded.tickSchedule(now.Add(24 * time.Hour))
	if reloaded.cfg.Mode != "dormir" {
		t.Fatal("next day skipped")
	}
	rules = append(rules, homeSchedule{ID: "other", At: "20:30", Mode: "fora", Enabled: true})
	if a.setSchedules(rules, now) == nil {
		t.Fatal("ambiguous automation accepted")
	}
}
func TestNotebookHealthTransitionsAndMotionPolicy(t *testing.T) {
	a := newAlerts(filepath.Join(t.TempDir(), "alerts.bin"), Config{})
	now := time.Now()
	plugged := powerReading{Known: true, AC: 1, HasBattery: true, Percent: 80, DiskKnown: true, DiskFree: 1024 * 1024 * 1024}
	a.updateHealth(plugged, now)
	if a.health.Level != "ok" || len(a.cfg.History) != 0 {
		t.Fatal("healthy startup spam")
	}
	battery := plugged
	battery.AC = 0
	a.updateHealth(battery, now.Add(time.Second))
	if a.health.Level != "ok" || a.cfg.History[len(a.cfg.History)-1].Code != "power_unplugged" {
		t.Fatal("unplugged not detected")
	}
	count := len(a.cfg.History)
	a.updateHealth(battery, now.Add(2*time.Second))
	if len(a.cfg.History) != count {
		t.Fatal("duplicate power alert")
	}
	battery.Percent = 20
	a.updateHealth(battery, now.Add(3*time.Second))
	if a.cfg.History[len(a.cfg.History)-1].Code != "battery_low" {
		t.Fatal("battery low")
	}
	battery.Percent = 8
	a.updateHealth(battery, now.Add(4*time.Second))
	if a.health.Level != "critical" {
		t.Fatal("battery critical")
	}
	a.updateHealth(plugged, now.Add(5*time.Second))
	if a.cfg.History[len(a.cfg.History)-1].Code != "power_ok" {
		t.Fatal("power recovery")
	}
	a.setMode("dormir", now)
	a.lastFrame = now
	a.updateHealth(plugged, now.Add(time.Second))
	a.updateHealth(plugged, now.Add(time.Minute))
	if a.health.Level != "critical" || a.cfg.History[len(a.cfg.History)-1].Code != "camera_lost" {
		t.Fatal("lost camera during monitoring")
	}
	a.lastFrame = now.Add(61 * time.Second)
	a.updateHealth(plugged, now.Add(62*time.Second))
	if a.cfg.History[len(a.cfg.History)-1].Code != "camera_ok" {
		t.Fatal("camera recovery")
	}
	a.updateHealth(powerReading{AC: -1, Percent: -1}, now.Add(63*time.Second))
	if a.health.Level != "unknown" {
		t.Fatal("unknown reported healthy")
	}
	// Separate motion notifications from retained motion events.
	p := a.cfg.Profiles["dormir"]
	p.Notify = false
	a.setProfile("dormir", p, now)
	for len(a.events) > 0 {
		<-a.events
	}
	blank := make([]byte, frameSize)
	box := bytes.Clone(blank)
	for y := 20; y < 60; y++ {
		for x := 20; x < 80; x++ {
			box[y*frameWidth+x] = 220
		}
	}
	for i := 0; i < 8; i++ {
		a.frame(blank)
	}
	for i := 0; i < 6; i++ {
		if i%2 == 0 {
			a.frame(box)
		} else {
			a.frame(blank)
		}
	}
	if a.latest.ID == 0 || len(a.events) != 0 || a.cfg.History[len(a.cfg.History)-1].Kind != "motion" {
		t.Fatal("motion policy or metadata failed")
	}
}
func TestHomeAPIAuthorizationAndSettingsIsolation(t *testing.T) {
	b := testBridge(t)
	paths := []string{"/api/home", "/api/home/mode", "/api/home/profile", "/api/home/schedules", "/api/home/health", "/api/home/history/clear"}
	cookie, csrf := login(t, b)
	for _, path := range paths {
		method := "POST"
		if path == "/api/home" {
			method = "GET"
		}
		if req(b, method, path, "viewer.test", map[string]any{}, nil, "").Code != 401 {
			t.Fatal("anonymous home access", path)
		}
		if method == "POST" && req(b, method, path, "viewer.test", map[string]any{}, cookie, "").Code != 403 {
			t.Fatal("CSRF", path)
		}
	}
	r := req(b, "POST", "/api/home/mode", "viewer.test", map[string]any{"mode": "dormir"}, cookie, csrf)
	if r.Code != 200 || !b.alerts.enabled() {
		t.Fatal("mode API", r.Code)
	}
	if req(b, "POST", "/api/home/profile", "viewer.test", map[string]any{"mode": "dormir", "profile": map[string]any{"enabled": true, "notifications": true, "sensitivity": "invented", "cooldownSeconds": 0}}, cookie, csrf).Code != 400 {
		t.Fatal("invalid profile")
	}
	text := req(b, "GET", "/api/home", "viewer.test", nil, cookie, "").Body.String()
	for _, secret := range []string{"privateKey", "subscriptions", "password", "config.bin"} {
		if strings.Contains(text, secret) {
			t.Fatal("private home field", secret)
		}
	}
	if req(b, "POST", "/api/home/history/clear", "viewer.test", map[string]any{}, cookie, csrf).Code != 200 || len(b.alerts.cfg.History) != 0 {
		t.Fatal("clear history")
	}
}
