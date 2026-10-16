package main

import (
	"testing"
	"time"
)

func TestWaitForReportsWhetherDoneClosedInTime(t *testing.T) {
	done := make(chan struct{})
	if waitFor(done, 10*time.Millisecond) {
		t.Fatal("reported done before the channel closed")
	}
	go close(done)
	if !waitFor(done, 5*time.Second) {
		t.Fatal("did not see the channel close")
	}
}
