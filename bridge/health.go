package main

import "time"

func levelRank(level string) int {
	switch level {
	case "critical":
		return 3
	case "attention":
		return 2
	case "unknown":
		return 1
	}
	return 0
}
func (a *alertManager) updateHealth(p powerReading, now time.Time) {
	a.mu.Lock()
	defer a.mu.Unlock()
	h := homeHealth{CheckedAt: now, Level: "ok", Items: []healthItem{}}
	add := func(code, level string) {
		h.Items = append(h.Items, healthItem{code, level})
		if levelRank(level) > levelRank(h.Level) {
			h.Level = level
		}
	}
	power := "power_ok"
	if !p.Known {
		power = "power_unknown"
		add(power, "unknown")
	} else {
		if p.HasBattery && p.Percent >= 0 {
			v := p.Percent
			h.Battery = &v
		}
		switch {
		case p.HasBattery && p.AC != 1 && p.Percent >= 0 && p.Percent <= 10:
			power = "battery_critical"
			add(power, "critical")
		case p.HasBattery && p.AC != 1 && p.Percent >= 0 && p.Percent <= 25:
			power = "battery_low"
			add(power, "attention")
		case p.AC == 0:
			power = "power_unplugged"
			level := "attention"
			if p.HasBattery && p.Percent > 25 {
				level = "info"
			}
			add(power, level)
		case p.AC < 0:
			power = "power_unknown"
			add(power, "unknown")
		default:
			add(power, "ok")
		}
	}
	storage := "storage_ok"
	if p.DiskKnown && p.DiskFree < 512*1024*1024 {
		storage = "storage_low"
		add(storage, "attention")
	}
	camera := "not_monitoring"
	if a.cfg.Enabled {
		camera = "camera_pending"
		if !a.lastFrame.IsZero() && now.Sub(a.lastFrame) < 15*time.Second {
			camera = "camera_ok"
			add(camera, "ok")
		} else if now.Sub(a.monitorSince) > 45*time.Second {
			camera = "camera_lost"
			add(camera, "critical")
		} else {
			add(camera, "unknown")
		}
	}
	nextStates := map[string]string{"power": power, "storage": storage, "camera": camera}
	for _, name := range []string{"power", "storage", "camera"} {
		code := nextStates[name]
		old := a.healthStates[name]
		if old == code {
			continue
		}
		severity := "attention"
		if code == "power_unplugged" && p.HasBattery && p.Percent > 25 {
			severity = "info"
		}
		if code == "battery_critical" || code == "camera_lost" {
			severity = "critical"
		}
		recovery := (code == "power_ok" || code == "storage_ok" || code == "camera_ok") && old != "" && old != "camera_pending" && old != "not_monitoring"
		warning := code == "power_unplugged" || code == "battery_low" || code == "battery_critical" || code == "storage_low" || code == "camera_lost"
		if recovery {
			severity = "ok"
		}
		if warning || recovery {
			a.recordLocked("health", code, severity, now)
			if a.cfg.HealthNotices {
				select {
				case a.events <- alertEvent{ID: a.cfg.NextEvent, At: now, Generation: a.generation, Kind: "health", Code: code}:
				default:
				}
			}
		}
	}
	a.healthStates = nextStates
	a.health = h
	// Prune persisted metadata too, including on quiet days with no new motion.
	pruned := pruneHistory(a.cfg.History, now)
	if len(pruned) != len(a.cfg.History) {
		next := a.cfg
		next.History = pruned
		if a.saveLocked(next) != nil {
			a.code = "historico_nao_salvo"
		}
	}
}
