package repoconfig

import (
	"strings"
	"testing"
)

// The screenshot capture renders every frame on four devices and writes
// files; it is a tool, not a check, so the gate never runs it.
func TestCheckSkipsTheStoreScreenCapture(t *testing.T) {
	mk := read(t, "Makefile")
	if !strings.Contains(mk, "flutter test --exclude-tags store_screens") {
		t.Error("make dart-test must run flutter test --exclude-tags store_screens")
	}
	if !strings.Contains(mk, "store-screens-raw:") {
		t.Error("Makefile needs the store-screens-raw target")
	}
	if !strings.Contains(read(t, "app/test/store_screens/store_screens_test.dart"), "@Tags(['store_screens'])") {
		t.Error("the capture test must carry @Tags(['store_screens'])")
	}
}
