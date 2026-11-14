package main

import (
	"bufio"
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"net/textproto"
	"net/url"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

func itoa(n int) string      { return strconv.Itoa(n) }
func md5hex(s string) string { b := md5.Sum([]byte(s)); return hex.EncodeToString(b[:]) }

var authFields = regexp.MustCompile(`(\w+)=(?:"([^"]*)"|([^,\s]+))`)

func authorization(challenge, method, uri, user, password string, nc int) string {
	if strings.HasPrefix(strings.ToLower(challenge), "basic ") {
		return "Basic " + base64.StdEncoding.EncodeToString([]byte(user+":"+password))
	}
	f := map[string]string{}
	for _, m := range authFields.FindAllStringSubmatch(challenge, -1) {
		v := m[2]
		if v == "" {
			v = m[3]
		}
		f[strings.ToLower(m[1])] = v
	}
	if f["nonce"] == "" {
		return ""
	}
	alg := strings.ToUpper(f["algorithm"])
	if alg != "" && alg != "MD5" && alg != "MD5-SESS" {
		return ""
	}
	cn := randomID()[:16]
	a := md5hex(user + ":" + f["realm"] + ":" + password)
	if alg == "MD5-SESS" {
		a = md5hex(a + ":" + f["nonce"] + ":" + cn)
	}
	qop := ""
	for _, q := range strings.Split(f["qop"], ",") {
		if strings.TrimSpace(q) == "auth" {
			qop = "auth"
		}
	}
	if f["qop"] != "" && qop == "" {
		return ""
	}
	count := fmt.Sprintf("%08x", nc)
	response := md5hex(a + ":" + f["nonce"] + ":" + md5hex(method+":"+uri))
	if qop != "" {
		response = md5hex(a + ":" + f["nonce"] + ":" + count + ":" + cn + ":" + qop + ":" + md5hex(method+":"+uri))
	}
	quote := func(v string) string { return strings.ReplaceAll(strings.ReplaceAll(v, `\`, `\\`), `"`, `\"`) }
	out := fmt.Sprintf(`Digest username="%s", realm="%s", nonce="%s", uri="%s", response="%s"`, quote(user), quote(f["realm"]), quote(f["nonce"]), quote(uri), response)
	if alg != "" {
		out += `, algorithm=` + alg
	}
	if qop != "" {
		out += fmt.Sprintf(`, qop=auth, nc=%s, cnonce="%s"`, count, cn)
	}
	if f["opaque"] != "" {
		out += `, opaque="` + quote(f["opaque"]) + `"`
	}
	return out
}

type wire struct {
	line  string
	h     textproto.MIMEHeader
	body  []byte
	frame []byte
}

func readWire(r *bufio.Reader) (wire, error) {
	var w wire
	b, e := r.Peek(1)
	for skipped := 0; e == nil && (b[0] == '\r' || b[0] == '\n'); skipped++ {
		if skipped >= 8 {
			return w, errors.New("rtsp_padding")
		}
		r.ReadByte()
		b, e = r.Peek(1)
	}
	if e != nil {
		return w, e
	}
	if b[0] == '$' {
		head := make([]byte, 4)
		if _, e = io.ReadFull(r, head); e != nil {
			return w, e
		}
		n := int(head[2])<<8 | int(head[3])
		w.frame = make([]byte, n+4)
		copy(w.frame, head)
		_, e = io.ReadFull(r, w.frame[4:])
		return w, e
	}
	line, e := r.ReadString('\n')
	if e != nil {
		return w, e
	}
	if len(line) > 8192 {
		return w, errors.New("rtsp_line")
	}
	w.line = strings.TrimSpace(line)
	w.h = make(textproto.MIMEHeader)
	size := len(line)
	for {
		line, e = r.ReadString('\n')
		if e != nil {
			return w, e
		}
		size += len(line)
		if size > 65536 {
			return w, errors.New("rtsp_header")
		}
		line = strings.TrimSpace(line)
		if line == "" {
			break
		}
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			return w, errors.New("rtsp_header")
		}
		w.h.Add(key, strings.TrimSpace(value))
	}
	n := 0
	if raw := w.h.Get("Content-Length"); raw != "" {
		n, e = strconv.Atoi(raw)
		if e != nil || n < 0 || n > 1024*1024 {
			return w, errors.New("rtsp_body")
		}
	}
	w.body = make([]byte, n)
	_, e = io.ReadFull(r, w.body)
	return w, e
}
func writeWire(c net.Conn, w wire) error {
	if w.frame != nil {
		_, e := c.Write(w.frame)
		return e
	}
	var out strings.Builder
	out.WriteString(w.line + "\r\n")
	if len(w.body) > 0 || w.h.Get("Content-Length") != "" {
		w.h.Set("Content-Length", itoa(len(w.body)))
	}
	for k, vs := range w.h {
		for _, v := range vs {
			name := k
			if strings.EqualFold(k, "cseq") {
				name = "CSeq"
			}
			out.WriteString(name + ": " + v + "\r\n")
		}
	}
	out.WriteString("\r\n")
	out.Write(w.body)
	_, e := io.WriteString(c, out.String())
	return e
}

var interleave = regexp.MustCompile(`(?i)(?:^|;)\s*interleaved=(\d+)-(\d+)(?:;|$)`)

func normalizeTransport(received, asked string) string {
	a := interleave.FindStringSubmatch(asked)
	b := interleave.FindStringSubmatch(received)
	parts := strings.SplitN(received, ";", 2)
	if strings.EqualFold(parts[0], "RTP/AVP") && !regexp.MustCompile(`(?i)server_port|client_port|multicast`).MatchString(received) && strings.Contains(strings.ToUpper(asked), "RTP/AVP/TCP") && len(a) == 3 && len(b) == 3 && a[1] == b[1] && a[2] == b[2] {
		parts[0] = "RTP/AVP/TCP"
		return strings.Join(parts, ";")
	}
	return received
}

type rtspRelay struct {
	listener net.Listener
	cfg      Config
	mu       sync.Mutex
	conns    []net.Conn
	closed   bool
	token    string
	onEvent  func(string, string, int, int, bool)
}

func newRelay(c Config) (*rtspRelay, error) { return newRelayWithEvents(c, nil) }
func newRelayWithEvents(c Config, event func(string, string, int, int, bool)) (*rtspRelay, error) {
	l, e := net.Listen("tcp4", "127.0.0.1:0")
	if e != nil {
		return nil, e
	}
	p := &rtspRelay{listener: l, cfg: c, token: randomID(), onEvent: event}
	go func() {
		for {
			local, e := l.Accept()
			if e != nil {
				return
			}
			go p.serve(local)
		}
	}()
	return p, nil
}
func (p *rtspRelay) url() string {
	return "rtsp://" + p.listener.Addr().String() + "/" + p.token + p.cfg.Path
}
func (p *rtspRelay) close() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.closed = true
	p.listener.Close()
	for _, c := range p.conns {
		c.Close()
	}
}
func (p *rtspRelay) emit(stage, method string, status, bytes int, repair bool) {
	if p.onEvent != nil {
		p.onEvent(stage, method, status, bytes, repair)
	}
}
func (p *rtspRelay) serve(local net.Conn) {
	defer local.Close()
	p.emit("conectando_camera", "", 0, 0, false)
	remote, e := net.DialTimeout("tcp", net.JoinHostPort(p.cfg.Host, itoa(p.cfg.Port)), 5*time.Second)
	if e != nil {
		p.emit(cameraConnectionError(e), "", 0, 0, false)
		return
	}
	p.emit("controle_rtsp_conectado", "", 0, 0, false)
	defer remote.Close()
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return
	}
	p.conns = append(p.conns, local, remote)
	p.mu.Unlock()
	defer func() {
		p.mu.Lock()
		defer p.mu.Unlock()
		for i := len(p.conns) - 1; i >= 0; i-- {
			if p.conns[i] == local || p.conns[i] == remote {
				p.conns = append(p.conns[:i], p.conns[i+1:]...)
			}
		}
	}()
	target := "rtsp://" + remote.RemoteAddr().String()
	source := "rtsp://" + p.listener.Addr().String() + "/" + p.token
	var mu, writeMu sync.Mutex
	pending := map[string]wire{}
	attempts := map[string]int{}
	challenge := ""
	nc := 0
	send := func(w wire) error {
		writeMu.Lock()
		defer writeMu.Unlock()
		mu.Lock()
		if challenge != "" {
			fields := strings.Fields(w.line)
			nc++
			w.h.Set("Authorization", authorization(challenge, fields[0], fields[1], p.cfg.User, p.cfg.Password, nc))
		}
		mu.Unlock()
		return writeWire(remote, w)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		defer remote.Close()
		defer local.Close()
		r := bufio.NewReader(local)
		for {
			w, e := readWire(r)
			if e != nil {
				return
			}
			if w.frame != nil {
				writeMu.Lock()
				e = writeWire(remote, w)
				writeMu.Unlock()
				if e != nil {
					return
				}
				continue
			}
			fields := strings.Fields(w.line)
			if len(fields) != 3 || !strings.HasPrefix(fields[1], source+"/") {
				return
			}
			p.emit("negociando_rtsp", fields[0], 0, 0, false)
			w.line = strings.ReplaceAll(w.line, source, target)
			w.h.Del("Authorization")
			seq := w.h.Get("Cseq")
			mu.Lock()
			pending[seq] = w
			mu.Unlock()
			if e = send(w); e != nil {
				return
			}
		}
	}()
	r := bufio.NewReader(remote)
	for {
		w, e := readWire(r)
		if e != nil {
			if !errors.Is(e, net.ErrClosed) {
				code := "camera_resposta_rtsp_invalida"
				if errors.Is(e, io.EOF) || errors.Is(e, io.ErrUnexpectedEOF) {
					code = "camera_encerrou_conexao"
				} else if ne, ok := e.(net.Error); ok && ne.Timeout() {
					code = "camera_sem_resposta"
				}
				p.emit(code, "", 0, 0, false)
			}
			return
		}
		if w.frame != nil {
			p.emit("recebendo_midia_rtsp", "", 0, len(w.frame), false)
			if writeWire(local, w) != nil {
				return
			}
			continue
		}
		seq := w.h.Get("Cseq")
		mu.Lock()
		req, ok := pending[seq]
		retry := ok && strings.Contains(w.line, " 401 ") && attempts[seq] == 0 && w.h.Get("Www-Authenticate") != ""
		if retry {
			challenge = w.h.Get("Www-Authenticate")
			attempts[seq]++
		} else {
			delete(pending, seq)
			delete(attempts, seq)
		}
		mu.Unlock()
		status := 0
		fields := strings.Fields(w.line)
		if len(fields) > 1 {
			status, _ = strconv.Atoi(fields[1])
		}
		method := ""
		if ok {
			f := strings.Fields(req.line)
			if len(f) > 0 {
				method = f[0]
			}
		}
		p.emit("resposta_rtsp", method, status, 0, false)
		if retry {
			if e = send(req); e != nil {
				return
			}
			continue
		}
		before := w.h.Get("Transport")
		after := normalizeTransport(before, req.h.Get("Transport"))
		if before != after {
			p.emit("compatibilidade_tcp_aplicada", method, status, 0, true)
		}
		w.h.Set("Transport", after)
		if w.h.Get("Transport") == "" {
			w.h.Del("Transport")
		}
		for _, key := range []string{"Content-Base", "Content-Location", "Location"} {
			if v := w.h.Get(key); v != "" {
				w.h.Set(key, rewriteCameraURIs(v, p.cfg, source))
			}
		}
		w.body = []byte(rewriteCameraURIs(string(w.body), p.cfg, source))
		if writeWire(local, w) != nil {
			return
		}
	}
}

var cameraURI = regexp.MustCompile(`(?i)rtsp://[^\s<>"',;]+`)

func rewriteCameraURIs(value string, cfg Config, source string) string {
	return cameraURI.ReplaceAllStringFunc(value, func(raw string) string {
		u, e := url.Parse(raw)
		if e != nil || u.Hostname() != cfg.Host {
			return raw
		}
		port := u.Port()
		if port == "" {
			port = "554"
		}
		if port != itoa(cfg.Port) {
			return raw
		}
		base, _ := url.Parse(source)
		u.Host = base.Host
		u.User = nil
		u.Path = base.Path + u.Path
		return u.String()
	})
}

// Retain only stable error codes, never the address/credentials from OpError.
func cameraConnectionError(err error) string {
	var ne net.Error
	if errors.As(err, &ne) && ne.Timeout() {
		return "camera_sem_resposta"
	}
	if errors.Is(err, syscall.ECONNREFUSED) {
		return "camera_recusou_conexao"
	}
	if errors.Is(err, syscall.ENETUNREACH) || errors.Is(err, syscall.EHOSTUNREACH) {
		return "camera_fora_da_rede"
	}
	// Winsock's native error numbers differ from Go's portable errno constants.
	if runtime.GOOS == "windows" {
		var code syscall.Errno
		if errors.As(err, &code) {
			switch code {
			case 10061:
				return "camera_recusou_conexao"
			case 10060:
				return "camera_sem_resposta"
			case 10051, 10065:
				return "camera_fora_da_rede"
			}
		}
	}
	return "camera_sem_conexao"
}
