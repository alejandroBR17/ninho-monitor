package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestProfileAndZeroPreflight(t *testing.T) {
	var base string
	var ops []string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data, _ := io.ReadAll(r.Body)
		n, e := tree(data)
		if e != nil {
			t.Error(e)
			return
		}
		out := ""
		switch {
		case n.find("GetCapabilities") != nil:
			ops = append(ops, "caps")
			out = `<GetCapabilitiesResponse><Capabilities><Media><XAddr>` + base + `/media</XAddr></Media><PTZ><XAddr>` + base + `/io</XAddr></PTZ></Capabilities></GetCapabilitiesResponse>`
		case n.find("GetProfiles") != nil:
			ops = append(ops, "profiles")
			out = `<GetProfilesResponse><Profiles token="actual-profile"><PTZConfiguration token="cfg"/></Profiles></GetProfilesResponse>`
		case n.find("ContinuousMove") != nil:
			ops = append(ops, "move")
			if !strings.Contains(string(data), "<tptz:ContinuousMove>") || n.value("ProfileToken") != "actual-profile" {
				t.Error("wire profile/prefix")
			}
			tilt := n.find("PanTilt")
			if len(ops) == 3 && (tilt.attr("x") != "0.0" || tilt.attr("y") != "0.0" || n.find("Timeout") != nil) {
				t.Error("preflight moved")
			}
			if len(ops) == 4 && n.value("Timeout") != "PT2S" {
				t.Error("timeout missing")
			}
			if len(n.value("MessageID")) != 45 {
				t.Error("message ID")
			}
			out = `<ContinuousMoveResponse/>`
		default:
			t.Error("unexpected operation")
		}
		w.Write([]byte(`<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body>` + out + `</s:Body></s:Envelope>`))
	}))
	defer server.Close()
	base = server.URL
	u, _ := url.Parse(base)
	p := newCameraPTZ(Config{Host: u.Hostname(), OnvifPort: portOf(u), User: "fixture", Password: "private-fixture"})
	if e := p.prepare(context.Background()); e != nil {
		t.Fatal(e)
	}
	if e := p.move(context.Background(), 1, 0); e != nil {
		t.Fatal(e)
	}
	if len(ops) != 4 {
		t.Fatal(ops)
	}
}
func portOf(u *url.URL) int {
	n := 0
	for _, r := range u.Port() {
		n = n*10 + int(r-'0')
	}
	return n
}
