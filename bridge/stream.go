package main

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

type videoDiagnostic struct {
	Stage            string `json:"etapa"`
	Method           string `json:"ultimoMetodoRtsp,omitempty"`
	Status           int    `json:"ultimoStatusRtsp,omitempty"`
	Packets          int64  `json:"pacotesIntercalados"`
	Bytes            int64  `json:"bytesIntercalados"`
	Frames           int64  `json:"quadrosConvertidos"`
	TransportRepairs int64  `json:"correcoesTcp"`
	Hint             string `json:"sinalConversor,omitempty"`
	ElapsedMS        int64  `json:"preparacaoMs"`
}
type streamManager struct {
	mu            sync.Mutex
	lifecycle     sync.Mutex
	done          chan struct{}
	cfg           Config
	binary, dir   string
	cmd           *exec.Cmd
	cancel        context.CancelFunc
	relay         *rtspRelay
	last, started time.Time
	errorCode     string
	starting      bool
	generation    uint64
	diag          videoDiagnostic
	alerts        *alertManager
	launch        func(*exec.Cmd) error // Injected only by process-start regression tests.
}

func (s *streamManager) update(g uint64, fn func(*videoDiagnostic)) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.generation == g {
		fn(&s.diag)
	}
}
func (s *streamManager) start() error {
	s.lifecycle.Lock()
	defer s.lifecycle.Unlock()
	s.mu.Lock()
	stale := s.staleLocked(time.Now())
	s.mu.Unlock()
	if stale {
		s.stopLocked()
	}
	s.mu.Lock()
	s.last = time.Now()
	if s.cmd != nil || s.starting {
		s.mu.Unlock()
		return nil
	}
	s.generation++
	g := s.generation
	s.starting = true
	s.started = time.Now()
	s.diag = videoDiagnostic{Stage: "iniciando_conversor"}
	s.errorCode = ""
	cfg := s.cfg
	ctx, cancel := context.WithCancel(context.Background())
	s.cancel = cancel
	s.mu.Unlock()
	// Never hold the status mutex while Windows starts/scans a large executable.
	fail := func(code string) {
		s.mu.Lock()
		if s.generation == g {
			s.starting = false
			s.errorCode = code
			s.diag.Stage = "falha"
		}
		s.mu.Unlock()
		cancel()
	}
	os.RemoveAll(s.dir)
	if e := os.MkdirAll(s.dir, 0700); e != nil {
		fail("pasta_video_sem_acesso")
		return e
	}
	relay, e := newRelayWithEvents(cfg, func(stage, method string, status int, packetBytes int, repair bool) {
		s.update(g, func(d *videoDiagnostic) {
			if d.Frames == 0 {
				d.Stage = stage
			}
			if method != "" {
				d.Method = method
			}
			if status != 0 {
				d.Status = status
			}
			if packetBytes > 0 {
				d.Packets++
				d.Bytes += int64(packetBytes)
			}
			if repair {
				d.TransportRepairs++
			}
			if strings.HasPrefix(stage, "camera_") {
				d.Hint = stage
			}
		})
	})
	if e != nil {
		fail("ponte_rtsp_nao_iniciou")
		return e
	}
	args := []string{"-hide_banner", "-loglevel", "error", "-nostats", "-progress", "pipe:2", "-rtsp_transport", "tcp", "-timeout", "10000000", "-analyzeduration", "10000000", "-probesize", "10000000", "-i", relay.url(), "-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale=640:360:force_original_aspect_ratio=decrease,pad=640:360:(ow-iw)/2:(oh-ih)/2", "-r", "15", "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency", "-profile:v", "baseline", "-pix_fmt", "yuv420p", "-b:v", "900k", "-maxrate", "1100k", "-bufsize", "1800k", "-g", "15", "-keyint_min", "15", "-sc_threshold", "0", "-threads", "2", "-c:a", "aac", "-ar", "16000", "-ac", "1", "-b:a", "64k", "-f", "hls", "-hls_time", "1", "-hls_list_size", "8", "-hls_flags", "delete_segments+independent_segments+temp_file", "-hls_segment_filename", filepath.Join(s.dir, "segment-%09d.ts"), filepath.Join(s.dir, "live.m3u8")}
	cmd := exec.CommandContext(ctx, s.binary, args...)
	if s.alerts != nil {
		s.alerts.resetFrames()
		args = append(args, "-map", "0:v:0", "-an", "-vf", "fps=2,scale=160:90,format=gray", "-threads", "1", "-f", "rawvideo", "pipe:1")
		cmd.Args = append([]string{s.binary}, args...)
		cmd.Stdout = &frameSink{frame: s.alerts.frame}
	} else {
		cmd.Stdout = io.Discard
	}
	cmd.Stderr = &lineSink{line: func(line string) {
		if strings.HasPrefix(line, "frame=") {
			n, _ := strconv.ParseInt(strings.TrimSpace(strings.TrimPrefix(line, "frame=")), 10, 64)
			s.update(g, func(d *videoDiagnostic) {
				d.Frames = n
				if n > 0 {
					d.Stage = "convertendo_video"
				}
			})
		}
		if code := classifyConverterError(line); code != "" {
			s.update(g, func(d *videoDiagnostic) { d.Hint = code })
		}
	}}
	start := s.launch
	if start == nil {
		start = func(c *exec.Cmd) error { return c.Start() }
	}
	if e = start(cmd); e != nil {
		relay.close()
		fail("conversor_nao_iniciou")
		return e
	}
	if e = attachProcess(cmd); e != nil {
		cancel()
		cmd.Wait()
		relay.close()
		fail("processo_windows_nao_protegido")
		return e
	}
	s.mu.Lock()
	s.starting = false
	s.cmd = cmd
	s.relay = relay
	done := make(chan struct{})
	s.done = done
	if s.diag.Stage == "iniciando_conversor" {
		s.diag.Stage = "aguardando_conexao_rtsp"
	}
	s.mu.Unlock()
	go func() {
		defer close(done)
		cmd.Wait()
		relay.close()
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.generation == g && s.cmd == cmd {
			s.cmd = nil
			if s.errorCode == "" {
				s.errorCode = s.diag.Hint
				if s.errorCode == "" {
					s.errorCode = "video_interrompido"
				}
			}
			s.diag.Stage = "falha"
		}
	}()
	go func() {
		timer := time.NewTimer(45 * time.Second)
		defer timer.Stop()
		select {
		case <-ctx.Done():
			return
		case <-done:
			return
		case <-timer.C:
		}
		s.mu.Lock()
		_, err := os.Stat(filepath.Join(s.dir, "live.m3u8"))
		if s.generation == g && s.cmd == cmd && err != nil {
			s.errorCode = "primeiro_video_timeout"
			s.diag.Stage = "falha"
			cancel()
			relay.close()
		}
		s.mu.Unlock()
	}()
	return nil
}

// Viewer renewals and expiry share the lifecycle lock: a renewal cannot be
// lost between the idle decision and process teardown.
func (s *streamManager) touch() {
	s.lifecycle.Lock()
	defer s.lifecycle.Unlock()
	s.mu.Lock()
	s.last = time.Now()
	s.mu.Unlock()
}
func (s *streamManager) expireIdle(now time.Time) bool {
	s.lifecycle.Lock()
	defer s.lifecycle.Unlock()
	s.mu.Lock()
	idle := s.cmd != nil && now.Sub(s.last) > 90*time.Second && (s.alerts == nil || !s.alerts.enabled())
	s.mu.Unlock()
	if idle {
		s.stopLocked()
	}
	return idle
}
func (s *streamManager) stop() { s.lifecycle.Lock(); defer s.lifecycle.Unlock(); s.stopLocked() }
func (s *streamManager) stopLocked() {
	s.mu.Lock()
	s.generation++
	if s.cancel != nil {
		s.cancel()
	}
	if s.relay != nil {
		s.relay.close()
	}
	s.cmd = nil
	s.starting = false
	done := s.done
	s.mu.Unlock()
	if done != nil {
		select {
		case <-done:
		case <-time.After(5 * time.Second):
		}
	}
	os.RemoveAll(s.dir)
}
func (s *streamManager) idleLoop(ctx context.Context) {
	t := time.NewTicker(15 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			s.stop()
			return
		case <-t.C:
			s.expireIdle(time.Now())
		}
	}
}

// A playlist on disk is not evidence of a live converter. Share this check
// between status and start so reconnect can replace a hung process atomically.
// Call only while holding mu. The startup grace preserves slow HEVC probing.
func (s *streamManager) staleLocked(now time.Time) bool {
	if s.cmd == nil || s.starting {
		return false
	}
	info, err := os.Stat(filepath.Join(s.dir, "live.m3u8"))
	if err != nil {
		return !s.started.IsZero() && now.Sub(s.started) > 50*time.Second
	}
	return now.Sub(info.ModTime()) > 25*time.Second
}
func (s *streamManager) status() (bool, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.staleLocked(time.Now()) {
		return false, "video_sem_progresso"
	}
	_, e := os.Stat(filepath.Join(s.dir, "live.m3u8"))
	return s.cmd != nil && e == nil, s.errorCode
}
func (s *streamManager) diagnostic() videoDiagnostic {
	s.mu.Lock()
	defer s.mu.Unlock()
	d := s.diag
	if !s.started.IsZero() {
		d.ElapsedMS = time.Since(s.started).Milliseconds()
	}
	if s.staleLocked(time.Now()) {
		d.Stage = "video_sem_progresso"
		d.Hint = "playlist_sem_atualizacao"
	} else if s.cmd != nil {
		if _, e := os.Stat(filepath.Join(s.dir, "live.m3u8")); e == nil {
			d.Stage = "video_disponivel"
			d.Hint = ""
		}
	}
	return d
}

// Only classified codes are retained. Raw converter output may contain URLs.
type lineSink struct {
	buffer string
	line   func(string)
}

func (w *lineSink) Write(p []byte) (int, error) {
	w.buffer += string(p)
	for {
		line, rest, ok := strings.Cut(w.buffer, "\n")
		if !ok {
			break
		}
		w.buffer = rest
		w.line(strings.TrimSpace(line))
	}
	if len(w.buffer) > 4096 {
		w.buffer = ""
	}
	return len(p), nil
}
func classifyConverterError(line string) string {
	s := strings.ToLower(line)
	for _, rule := range []struct{ pattern, code string }{{"401 unauthorized", "autenticacao_camera_recusada"}, {"connection refused", "camera_recusou_conexao"}, {"nonmatching transport", "transporte_rtsp_recusado"}, {"unsupported transport", "transporte_rtsp_recusado"}, {"unrecognized option", "conversor_opcao_recusada"}, {"option not found", "conversor_opcao_recusada"}, {"permission denied", "pasta_video_sem_acesso"}, {"connection timed out", "camera_sem_resposta"}, {"operation timed out", "camera_sem_resposta"}, {"network is unreachable", "camera_fora_da_rede"}, {"404 not found", "caminho_rtsp_nao_encontrado"}, {"could not find codec parameters", "video_nao_identificado"}, {"invalid data found", "video_nao_identificado"}} {
		if strings.Contains(s, rule.pattern) {
			return rule.code
		}
	}
	return ""
}

var _ io.Writer = (*lineSink)(nil)
