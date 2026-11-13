package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"encoding/xml"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const ptzNS = "http://www.onvif.org/ver20/ptz/wsdl"
const schemaNS = "http://www.onvif.org/ver10/schema"

type node struct {
	Name     xml.Name
	Attrs    []xml.Attr
	Text     string
	Children []*node
}

func tree(data []byte) (*node, error) {
	d := xml.NewDecoder(bytes.NewReader(data))
	root := &node{}
	stack := []*node{root}
	for {
		t, e := d.Token()
		if e == io.EOF {
			break
		}
		if e != nil {
			return nil, e
		}
		switch v := t.(type) {
		case xml.StartElement:
			n := &node{Name: v.Name, Attrs: v.Attr}
			parent := stack[len(stack)-1]
			parent.Children = append(parent.Children, n)
			stack = append(stack, n)
		case xml.EndElement:
			stack = stack[:len(stack)-1]
		case xml.CharData:
			stack[len(stack)-1].Text += string(v)
		case xml.Directive:
			return nil, errors.New("xml_recusado")
		}
	}
	return root, nil
}
func (n *node) find(name string) *node {
	if n.Name.Local == name {
		return n
	}
	for _, c := range n.Children {
		if v := c.find(name); v != nil {
			return v
		}
	}
	return nil
}
func (n *node) value(name string) string {
	v := n.find(name)
	if v == nil {
		return ""
	}
	return strings.TrimSpace(v.Text)
}
func (n *node) attr(name string) string {
	for _, a := range n.Attrs {
		if a.Name.Local == name {
			return a.Value
		}
	}
	return ""
}
func esc(s string) string { var b bytes.Buffer; xml.EscapeText(&b, []byte(s)); return b.String() }

type cameraPTZ struct {
	cfg             Config
	client          *http.Client
	endpoint, token string
}

func newCameraPTZ(c Config) *cameraPTZ {
	return &cameraPTZ{cfg: c, client: &http.Client{Timeout: 4 * time.Second, Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true}, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}
func messageID() string {
	b := make([]byte, 16)
	rand.Read(b)
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	h := hex.EncodeToString(b)
	return h[:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:]
}
func (p *cameraPTZ) call(ctx context.Context, endpoint, ns, op, body string) (*node, error) {
	uri, e := url.Parse(endpoint)
	if e != nil || uri.Hostname() != p.cfg.Host || uri.Scheme != "http" || uri.User != nil {
		return nil, errors.New("endpoint_recusado")
	}
	nonce := make([]byte, 20)
	rand.Read(nonce)
	created := time.Now().UTC().Format("2006-01-02T15:04:05Z")
	digest := sha1.Sum(append(append(append([]byte{}, nonce...), []byte(created)...), []byte(p.cfg.Password)...))
	security := `<wsse:Security xmlns:wsse="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" xmlns:wsu="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd"><wsse:UsernameToken><wsse:Username>` + esc(p.cfg.User) + `</wsse:Username><wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">` + base64.StdEncoding.EncodeToString(digest[:]) + `</wsse:Password><wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">` + base64.StdEncoding.EncodeToString(nonce) + `</wsse:Nonce><wsu:Created>` + created + `</wsu:Created></wsse:UsernameToken></wsse:Security>`
	routing := `<wsa:Action>` + ns + `/` + op + `</wsa:Action><wsa:To>` + esc(endpoint) + `</wsa:To><wsa:MessageID>urn:uuid:` + messageID() + `</wsa:MessageID>`
	raw := `<?xml version="1.0"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:t="` + ns + `" xmlns:tt="` + schemaNS + `" xmlns:wsa="http://www.w3.org/2005/08/addressing"><s:Header>` + security + routing + `</s:Header><s:Body><t:` + op + `>` + body + `</t:` + op + `></s:Body></s:Envelope>`
	if ns == ptzNS {
		raw = strings.ReplaceAll(raw, "xmlns:t=", "xmlns:tptz=")
		raw = strings.ReplaceAll(raw, "<t:", "<tptz:")
		raw = strings.ReplaceAll(raw, "</t:", "</tptz:")
	}
	auth := ""
	for attempt := 0; attempt < 2; attempt++ {
		req, e := http.NewRequestWithContext(ctx, "POST", endpoint, strings.NewReader(raw))
		if e != nil {
			return nil, e
		}
		req.Close = true
		req.Header.Set("Content-Type", `application/soap+xml; charset=utf-8; action="`+ns+`/`+op+`"`)
		req.Header.Set("SOAPAction", `"`+ns+`/`+op+`"`)
		if auth != "" {
			req.Header.Set("Authorization", auth)
		}
		res, e := p.client.Do(req)
		if e != nil {
			return nil, errors.New("onvif_sem_resposta")
		}
		data, e := io.ReadAll(io.LimitReader(res.Body, 1024*1024+1))
		res.Body.Close()
		if e != nil || len(data) > 1024*1024 {
			return nil, errors.New("onvif_resposta_invalida")
		}
		if res.StatusCode == 401 && attempt == 0 {
			auth = authorization(res.Header.Get("WWW-Authenticate"), "POST", uri.RequestURI(), p.cfg.User, p.cfg.Password, 1)
			if auth != "" {
				continue
			}
		}
		if res.StatusCode != 200 {
			return nil, errors.New("onvif_http_recusado")
		}
		n, e := tree(data)
		if e != nil || n.find("Fault") != nil || n.find(op+"Response") == nil {
			return nil, errors.New("onvif_comando_nao_confirmado")
		}
		return n, nil
	}
	return nil, errors.New("onvif_autenticacao")
}
func (p *cameraPTZ) prepare(ctx context.Context) error {
	base := "http://" + net.JoinHostPort(p.cfg.Host, itoa(p.cfg.OnvifPort))
	caps, e := p.call(ctx, base+"/onvif/device_service", "http://www.onvif.org/ver10/device/wsdl", "GetCapabilities", "")
	if e != nil {
		return e
	}
	media, ptz := caps.find("Media"), caps.find("PTZ")
	if media == nil || ptz == nil {
		return errors.New("ptz_nao_anunciado")
	}
	p.endpoint = ptz.value("XAddr")
	profiles, e := p.call(ctx, media.value("XAddr"), "http://www.onvif.org/ver10/media/wsdl", "GetProfiles", "")
	if e != nil {
		return e
	}
	var scan func(*node)
	scan = func(n *node) {
		if p.token != "" {
			return
		}
		if n.Name.Local == "Profiles" && n.find("PTZConfiguration") != nil {
			p.token = n.attr("token")
			return
		}
		for _, c := range n.Children {
			scan(c)
		}
	}
	scan(profiles)
	if p.token == "" {
		return errors.New("perfil_ptz_ausente")
	}
	return p.move(ctx, 0, 0)
}
func (p *cameraPTZ) move(ctx context.Context, x, y int) error {
	body := `<t:ProfileToken>` + esc(p.token) + `</t:ProfileToken><t:Velocity><tt:PanTilt x="` + speed(x) + `" y="` + speed(y) + `"/></t:Velocity>`
	if x != 0 || y != 0 {
		body += `<t:Timeout>PT2S</t:Timeout>`
	}
	_, e := p.call(ctx, p.endpoint, ptzNS, "ContinuousMove", body)
	return e
}
func speed(v int) string {
	if v < 0 {
		return "-0.1"
	}
	if v > 0 {
		return "0.1"
	}
	return "0.0"
}
