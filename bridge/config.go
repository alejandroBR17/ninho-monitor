package main

import (
	"crypto/pbkdf2"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	Host      string `json:"host"`
	Port      int    `json:"port"`
	Path      string `json:"path"`
	User      string `json:"user"`
	Password  string `json:"password"`
	OnvifPort int    `json:"onvifPort"`
	Salt      string `json:"salt"`
	Hash      string `json:"hash"`
}

func (c Config) valid() bool {
	ip := net.ParseIP(c.Host)
	return ip != nil && (ip.IsPrivate() || ip.IsLoopback()) && c.Port > 0 && c.Port < 65536 && c.OnvifPort > 0 && c.OnvifPort < 65536 && strings.HasPrefix(c.Path, "/") && !strings.ContainsAny(c.Path, "\r\n ?#") && len(c.User) > 0 && len(c.Password) < 1024 && len(c.Hash) == 64 && len(c.Salt) == 32
}
func (c Config) cameraURL() *url.URL {
	return &url.URL{Scheme: "rtsp", Host: net.JoinHostPort(c.Host, itoa(c.Port)), Path: c.Path}
}
func randomID() string {
	b := make([]byte, 24)
	if _, e := rand.Read(b); e != nil {
		panic("random source unavailable")
	}
	return hex.EncodeToString(b)
}
func passwordHash(password, salt string) string {
	b, e := hex.DecodeString(salt)
	if e != nil {
		return ""
	}
	out, e := pbkdf2.Key(sha256.New, password, b, 210000, 32)
	if e != nil {
		return ""
	}
	return hex.EncodeToString(out)
}
func configurePassword(c *Config, password string) error {
	if len(password) < 12 || len(password) > 256 {
		return errors.New("use_12_caracteres")
	}
	c.Salt = randomID()[:32]
	c.Hash = passwordHash(password, c.Salt)
	return nil
}
func loadConfig(path string) (Config, error) {
	var c Config
	b, e := os.ReadFile(path)
	if e != nil {
		return c, e
	}
	b, e = unprotect(b)
	if e != nil {
		return c, e
	}
	e = json.Unmarshal(b, &c)
	if e == nil && !c.valid() {
		e = errors.New("configuracao_invalida")
	}
	return c, e
}
func saveConfig(path string, c Config) error {
	if !c.valid() {
		return errors.New("configuracao_invalida")
	}
	b, e := json.Marshal(c)
	if e != nil {
		return e
	}
	b, e = protect(b)
	if e != nil {
		return e
	}
	if e = os.MkdirAll(filepath.Dir(path), 0700); e != nil {
		return e
	}
	tmp := path + ".tmp"
	if e = os.WriteFile(tmp, b, 0600); e != nil {
		return e
	}
	return replaceFile(tmp, path)
}
