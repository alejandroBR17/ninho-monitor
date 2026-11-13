package main

import (
	"context"
	"errors"
	"sync"
	"time"
)

type motionIntent struct {
	X       int    `json:"x"`
	Y       int    `json:"y"`
	Gesture string `json:"gesture"`
	Seq     int64  `json:"seq"`
	Stop    bool   `json:"stop"`
}
type motion struct {
	mu                           sync.Mutex
	camera                       *cameraPTZ
	ready, preparing, terminated bool
	intent                       motionIntent
	owner                        string
	seq                          int64
	stopEpoch                    uint64
	heartbeat, start             time.Time
	closed                       map[string]time.Time
	wake                         chan struct{}
	cancel                       context.CancelFunc
	lastError                    string
}

func newMotion() *motion {
	return &motion{closed: map[string]time.Time{}, wake: make(chan struct{}, 1)}
}
func (m *motion) status() (bool, string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.ready, m.lastError
}
func (m *motion) prepare(c Config) error {
	m.mu.Lock()
	if m.terminated {
		m.mu.Unlock()
		return errors.New("controle_encerrado")
	}
	if m.ready {
		m.mu.Unlock()
		return nil
	}
	if m.preparing {
		m.mu.Unlock()
		return errors.New("controle_preparando")
	}
	m.preparing = true
	m.mu.Unlock()
	p := newCameraPTZ(c)
	ctx, cancel := context.WithTimeout(context.Background(), 16*time.Second)
	defer cancel()
	err := p.prepare(ctx)
	m.mu.Lock()
	m.preparing = false
	defer m.mu.Unlock()
	if m.terminated {
		return errors.New("controle_encerrado")
	}
	if err != nil {
		m.lastError = err.Error()
		return err
	}
	m.camera = p
	m.ready = true
	m.lastError = ""
	loopCtx, loopCancel := context.WithCancel(context.Background())
	m.cancel = loopCancel
	go m.run(loopCtx, p)
	return nil
}
func (m *motion) submit(owner string, i motionIntent) error {
	if i.X < -1 || i.X > 1 || i.Y < -1 || i.Y > 1 || len(i.Gesture) < 16 || len(i.Gesture) > 64 || i.Seq < 1 || i.Seq > 1e9 {
		return errors.New("comando_invalido")
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if !m.ready {
		return errors.New("controle_indisponivel")
	}
	now := time.Now()
	for k, t := range m.closed {
		if now.Sub(t) > time.Minute {
			delete(m.closed, k)
		}
	}
	key := owner + ":" + i.Gesture
	if _, ok := m.closed[key]; ok {
		return nil
	}
	active := m.intent.X != 0 || m.intent.Y != 0
	if active && m.owner != owner && !i.Stop {
		return errors.New("controle_em_uso")
	}
	if m.owner == owner && m.intent.Gesture == i.Gesture && i.Seq <= m.seq {
		return nil
	}
	if len(m.closed) > 256 {
		return errors.New("limite_controles")
	}
	if i.Stop || i.X == 0 && i.Y == 0 {
		m.stopEpoch++
		i.X = 0
		i.Y = 0
		m.closed[key] = now
		if active {
			m.closed[m.owner+":"+m.intent.Gesture] = now
		}
	} else if !active {
		m.start = now
	}
	if active && m.intent.Gesture != i.Gesture {
		m.closed[m.owner+":"+m.intent.Gesture] = now
	}
	m.owner = owner
	m.seq = i.Seq
	m.intent = i
	m.heartbeat = now
	select {
	case m.wake <- struct{}{}:
	default:
	}
	return nil
}
func (m *motion) run(ctx context.Context, p *cameraPTZ) {
	timer := time.NewTimer(time.Hour)
	defer timer.Stop()
	moving := false
	stoppedEpoch := uint64(0)
	lastSent := time.Time{}
	for {
		select {
		case <-ctx.Done():
			if moving {
				stop, cancel := context.WithTimeout(context.Background(), 4*time.Second)
				p.move(stop, 0, 0)
				cancel()
			}
			return
		case <-m.wake:
		case <-timer.C:
		}
		m.mu.Lock()
		i := m.intent
		now := time.Now()
		if (i.X != 0 || i.Y != 0) && (now.Sub(m.heartbeat) > 1500*time.Millisecond || now.Sub(m.start) >= 5*time.Second) {
			m.closed[m.owner+":"+i.Gesture] = now
			m.intent.X = 0
			m.intent.Y = 0
			i.X = 0
			i.Y = 0
		}
		epoch := m.stopEpoch
		mustStop := epoch > stoppedEpoch
		if mustStop {
			i.X = 0
			i.Y = 0
		}
		m.mu.Unlock()
		nonzero := i.X != 0 || i.Y != 0
		if nonzero && moving && time.Since(lastSent) < 400*time.Millisecond {
			if !timer.Stop() {
				select {
				case <-timer.C:
				default:
				}
			}
			timer.Reset(400*time.Millisecond - time.Since(lastSent))
			continue
		}
		if !nonzero && !moving && !mustStop {
			continue
		}
		start := time.Now()
		lastSent = start
		err := p.move(ctx, i.X, i.Y)
		moving = nonzero
		if !nonzero && err == nil {
			stoppedEpoch = epoch
		}
		if err != nil {
			stop, cancel := context.WithTimeout(context.Background(), 4*time.Second)
			p.move(stop, 0, 0)
			cancel()
			m.mu.Lock()
			m.ready = false
			m.lastError = err.Error()
			m.mu.Unlock()
			return
		}
		delay := 400*time.Millisecond - time.Since(start)
		if delay < 0 {
			delay = 0
		}
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		m.mu.Lock()
		pending := m.intent.X != 0 || m.intent.Y != 0 || m.stopEpoch > stoppedEpoch
		m.mu.Unlock()
		if pending && !moving {
			delay = 0
		}
		if moving || pending {
			timer.Reset(delay)
		}
	}
}
func (m *motion) close() {
	m.mu.Lock()
	m.terminated = true
	if m.cancel != nil {
		m.cancel()
	}
	m.ready = false
	m.mu.Unlock()
}

func (m *motion) release(owner string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.owner == owner {
		m.stopEpoch++
		m.closed[owner+":"+m.intent.Gesture] = time.Now()
		m.intent.X = 0
		m.intent.Y = 0
		select {
		case m.wake <- struct{}{}:
		default:
		}
	}
}
