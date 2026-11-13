package main

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"
)

func TestDeadmanAndLateMoveCannotRestart(t *testing.T) {
	sent := make(chan [2]string, 20)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data, _ := io.ReadAll(r.Body)
		n, e := tree(data)
		if e != nil {
			t.Error(e)
			return
		}
		tilt := n.find("PanTilt")
		sent <- [2]string{tilt.attr("x"), tilt.attr("y")}
		w.Write([]byte(`<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><ContinuousMoveResponse/></s:Body></s:Envelope>`))
	}))
	defer server.Close()
	u, _ := url.Parse(server.URL)
	p := newCameraPTZ(Config{Host: u.Hostname(), User: "fixture", Password: "fixture"})
	p.endpoint = server.URL
	p.token = "received"
	m := newMotion()
	m.camera = p
	m.ready = true
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go m.run(ctx, p)
	i := motionIntent{X: 1, Gesture: "abcdefghijklmnop", Seq: 1}
	if e := m.submit("owner", i); e != nil {
		t.Fatal(e)
	}
	select {
	case v := <-sent:
		if v[0] != "0.1" {
			t.Fatal(v)
		}
	case <-time.After(time.Second):
		t.Fatal("no move")
	}
	if m.submit("other", i) == nil {
		t.Fatal("owner lease")
	}
	m.mu.Lock()
	m.heartbeat = time.Now().Add(-3 * time.Second)
	m.mu.Unlock()
	m.wake <- struct{}{}
	select {
	case v := <-sent:
		if v != [2]string{"0.0", "0.0"} {
			t.Fatal(v)
		}
	case <-time.After(time.Second):
		t.Fatal("deadman did not stop")
	}
	i.Seq = 2
	if e := m.submit("owner", i); e != nil {
		t.Fatal(e)
	}
	select {
	case v := <-sent:
		t.Fatal("late move restarted", v)
	case <-time.After(100 * time.Millisecond):
	}
}

func TestStopIsNotDroppedByNewGesture(t *testing.T) {
	sent := make(chan [2]string, 8)
	block := make(chan struct{})
	first := true
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data, _ := io.ReadAll(r.Body)
		n, _ := tree(data)
		tilt := n.find("PanTilt")
		v := [2]string{tilt.attr("x"), tilt.attr("y")}
		sent <- v
		if first {
			first = false
			<-block
		}
		w.Write([]byte(`<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><ContinuousMoveResponse/></s:Body></s:Envelope>`))
	}))
	defer server.Close()
	u, _ := url.Parse(server.URL)
	p := newCameraPTZ(Config{Host: u.Hostname(), User: "fixture", Password: "fixture"})
	p.endpoint = server.URL
	p.token = "profile"
	m := newMotion()
	m.ready = true
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go m.run(ctx, p)
	m.submit("owner", motionIntent{X: 1, Gesture: "gesture-first-123", Seq: 1})
	select {
	case <-sent:
	case <-time.After(time.Second):
		t.Fatal("no first move")
	}
	if e := m.submit("other", motionIntent{Stop: true, Gesture: "emergency-stop12", Seq: 1}); e != nil {
		t.Fatal("emergency blocked", e)
	}
	m.submit("owner", motionIntent{Y: 1, Gesture: "new-gesture-1234", Seq: 1})
	close(block)
	select {
	case v := <-sent:
		if v != [2]string{"0.0", "0.0"} {
			t.Fatal("stop dropped", v)
		}
	case <-time.After(time.Second):
		t.Fatal("no stop")
	}
	select {
	case v := <-sent:
		if v != [2]string{"0.0", "0.1"} {
			t.Fatal(v)
		}
	case <-time.After(time.Second):
		t.Fatal("new gesture not resumed")
	}
	m.release("owner")
}
