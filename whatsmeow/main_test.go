package main

import (
	"testing"
	"time"
)

func TestAllowCapsSendsPerHour(t *testing.T) {
	sess := &session{sent: []time.Time{time.Now().Add(-2 * time.Hour)}}

	for i := range 3 {
		if !sess.allow(3) {
			t.Fatalf("send %d should be allowed", i+1)
		}
	}
	if sess.allow(3) {
		t.Fatal("fourth send within the hour should be refused")
	}
	if len(sess.sent) != 3 {
		t.Fatalf("sends older than an hour should be dropped, got %d", len(sess.sent))
	}
}

func TestDelayStaysWithinBounds(t *testing.T) {
	l := limits{minDelay: 10 * time.Millisecond, maxDelay: 20 * time.Millisecond}
	for range 100 {
		if d := l.delay(); d < l.minDelay || d >= l.maxDelay {
			t.Fatalf("delay %v out of [%v, %v)", d, l.minDelay, l.maxDelay)
		}
	}
	if d := (limits{minDelay: 5}).delay(); d != 5 {
		t.Fatalf("without a range the delay is the minimum, got %v", d)
	}
}

func TestSessionIDs(t *testing.T) {
	for _, ok := range []string{"owner-1", "abc_DEF-9"} {
		if !sessionID.MatchString(ok) {
			t.Errorf("%q should be valid", ok)
		}
	}
	for _, bad := range []string{"", "../x", "a b", "a/b"} {
		if sessionID.MatchString(bad) {
			t.Errorf("%q should be invalid", bad)
		}
	}
}
