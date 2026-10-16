// Package clientip finds the address a request came from when it reaches
// the API through trusted proxies. The result is only an in-memory limiter key: never log it.
package clientip

import (
	"fmt"
	"net"
	"net/netip"
	"slices"
	"strings"
)

// ParseList reads a comma-separated list of CIDRs or bare addresses. A bare
// address is its own /32 or /128; blanks are skipped.
func ParseList(v string) ([]netip.Prefix, error) {
	var out []netip.Prefix
	for _, s := range strings.Split(v, ",") {
		if s = strings.TrimSpace(s); s == "" {
			continue
		}
		if p, err := netip.ParsePrefix(s); err == nil {
			// Addresses are unmapped before they are compared, so a mapped
			// prefix could never match.
			if p.Addr().Is4In6() {
				return nil, fmt.Errorf("%q is an IPv4-mapped prefix; write it as IPv4", s)
			}
			out = append(out, p.Masked())
			continue
		}
		a, err := netip.ParseAddr(s)
		if err != nil {
			return nil, fmt.Errorf("%q is neither a CIDR nor an address", s)
		}
		a = a.Unmap()
		out = append(out, netip.PrefixFrom(a, a.BitLen()))
	}
	return out, nil
}

// Resolve returns the peer in remoteAddr, unless the peer is trusted: then
// it walks the X-Forwarded-For values from the right, skipping trusted
// addresses, and returns the first one that is not. A proxy appends its
// peer to whatever the client sent, so only the right end is believable.
// An entry that does not parse ends the walk at the peer.
func Resolve(remoteAddr string, xff []string, trusted []netip.Prefix) string {
	host, _, err := net.SplitHostPort(remoteAddr)
	if err != nil {
		host = remoteAddr
	}
	peer, err := netip.ParseAddr(host)
	if err != nil || !contains(trusted, peer.Unmap()) {
		return host
	}
	var hops []string
	for _, v := range xff {
		hops = append(hops, strings.Split(v, ",")...)
	}
	for i := len(hops) - 1; i >= 0; i-- {
		a, err := netip.ParseAddr(strings.TrimSpace(hops[i]))
		if err != nil {
			return host
		}
		if a = a.Unmap(); !contains(trusted, a) {
			return a.String()
		}
	}
	return host
}

func contains(trusted []netip.Prefix, a netip.Addr) bool {
	return slices.ContainsFunc(trusted, func(p netip.Prefix) bool { return p.Contains(a) })
}
