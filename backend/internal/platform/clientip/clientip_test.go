package clientip_test

import (
	"net/netip"
	"slices"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/clientip"
)

var proxy = []netip.Prefix{netip.MustParsePrefix("10.0.0.0/8")}

func TestParseList(t *testing.T) {
	got, err := clientip.ParseList(" 10.0.0.0/8, 172.17.0.1 ,,2001:db8::/32, 2001:db8::1")
	if err != nil {
		t.Fatal(err)
	}
	want := []netip.Prefix{
		netip.MustParsePrefix("10.0.0.0/8"),
		netip.MustParsePrefix("172.17.0.1/32"),
		netip.MustParsePrefix("2001:db8::/32"),
		netip.MustParsePrefix("2001:db8::1/128"),
	}
	if !slices.Equal(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	if got, err := clientip.ParseList("  "); err != nil || got != nil {
		t.Fatalf("blank: %v %v, want nil nil", got, err)
	}
	for _, bad := range []string{"proxy.local", "10.0.0.0/33", "10.0.0.1:80", "::ffff:10.0.0.0/104"} {
		if _, err := clientip.ParseList("10.0.0.0/8," + bad); err == nil || !strings.Contains(err.Error(), `"`+bad+`"`) {
			t.Errorf("%s: %v, want an error naming it", bad, err)
		}
	}
}

func TestResolveKeepsThePeerWithoutTrust(t *testing.T) {
	xff := []string{"203.0.113.7"}
	if got := clientip.Resolve("10.0.0.2:4000", xff, nil); got != "10.0.0.2" {
		t.Fatalf("no trusted list: %q, want the peer", got)
	}
	if got := clientip.Resolve("198.51.100.9:4000", xff, proxy); got != "198.51.100.9" {
		t.Fatalf("untrusted peer: %q, want the peer", got)
	}
	if got := clientip.Resolve("not-an-address", xff, proxy); got != "not-an-address" {
		t.Fatalf("unparsable RemoteAddr: %q, want it as is", got)
	}
}

func TestResolveWalksForwardedForFromTheRight(t *testing.T) {
	cases := []struct {
		name string
		xff  []string
		want string
	}{
		{"one hop", []string{"203.0.113.7"}, "203.0.113.7"},
		{"forged prefix", []string{"1.1.1.1, 203.0.113.7"}, "203.0.113.7"},
		{"trusted hops skipped", []string{"203.0.113.7, 10.0.0.5"}, "203.0.113.7"},
		{"several header values", []string{"1.1.1.1", "203.0.113.7, 10.0.0.5"}, "203.0.113.7"},
		{"spaces", []string{" 203.0.113.7 ,10.0.0.5 "}, "203.0.113.7"},
	}
	for _, c := range cases {
		if got := clientip.Resolve("10.0.0.2:4000", c.xff, proxy); got != c.want {
			t.Errorf("%s: %q, want %q", c.name, got, c.want)
		}
	}
}

func TestResolveFallsBackToThePeer(t *testing.T) {
	for name, xff := range map[string][]string{
		"absent":             nil,
		"all trusted":        {"10.0.0.9, 10.0.0.5"},
		"unparsable":         {"203.0.113.7, garbage"},
		"with a port":        {"203.0.113.7:5000"},
		"empty segment":      {"203.0.113.7, , 10.0.0.5"},
		"empty header value": {""},
	} {
		if got := clientip.Resolve("10.0.0.2:4000", xff, proxy); got != "10.0.0.2" {
			t.Errorf("%s: %q, want the peer", name, got)
		}
	}
}

func TestResolveUnmapsIPv4InIPv6(t *testing.T) {
	if got := clientip.Resolve("[::ffff:10.0.0.3]:443", []string{"::ffff:203.0.113.7"}, proxy); got != "203.0.113.7" {
		t.Fatalf("mapped: %q, want 203.0.113.7", got)
	}
	v6 := []netip.Prefix{netip.MustParsePrefix("2001:db8::/32")}
	if got := clientip.Resolve("[2001:db8::1]:443", []string{"2001:db8:ffff::1, 2001:db8::2"}, v6); got != "2001:db8::1" {
		t.Fatalf("v6, every hop trusted: %q, want the peer", got)
	}
	if got := clientip.Resolve("[2001:db8::1]:443", []string{"2600::7"}, v6); got != "2600::7" {
		t.Fatalf("v6 client: %q, want 2600::7", got)
	}
}

func TestPortIsBelievedOnlyFromATrustedPeer(t *testing.T) {
	for _, c := range []struct {
		name, remote, header string
		want                 int
	}{
		{"trusted proxy", "10.0.0.2:4000", "51234", 51234},
		{"untrusted peer", "203.0.113.7:4000", "51234", 0},
		{"no header", "10.0.0.2:4000", "", 0},
		{"zero", "10.0.0.2:4000", "0", 0},
		{"too large", "10.0.0.2:4000", "65536", 0},
		{"two values", "10.0.0.2:4000", "80, 81", 0},
		{"padded highest", "10.0.0.2:4000", " 65535 ", 65535},
		{"peer without a port", "10.0.0.2", "443", 443},
	} {
		if got := clientip.Port(c.remote, c.header, proxy); got != c.want {
			t.Errorf("%s: %d, want %d", c.name, got, c.want)
		}
	}
	if got := clientip.Port("10.0.0.2:4000", "51234", nil); got != 0 {
		t.Errorf("no trusted proxies: %d, want 0", got)
	}
}
