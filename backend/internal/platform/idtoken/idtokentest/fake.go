// Package idtokentest fakes provider ID-token verification: a test issues
// opaque raw tokens that stand for chosen claims.
package idtokentest

import (
	"context"
	"fmt"
	"slices"
	"sync"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
)

type Fake struct {
	Disabled []idtoken.Provider

	mu     sync.Mutex
	tokens map[string]entry
}

type entry struct {
	p idtoken.Provider
	c idtoken.Claims
}

// Issue returns a new raw token that verifies, for p only, as c. A zero
// ExpiresAt becomes one hour after 2026-10-02 12:00 UTC.
func (f *Fake) Issue(p idtoken.Provider, c idtoken.Claims) string {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.tokens == nil {
		f.tokens = map[string]entry{}
	}
	if c.ExpiresAt.IsZero() {
		c.ExpiresAt = time.Date(2026, 10, 2, 13, 0, 0, 0, time.UTC)
	}
	raw := fmt.Sprintf("fake-%s-%d", p, len(f.tokens)+1)
	f.tokens[raw] = entry{p, c}
	return raw
}

func (f *Fake) Verify(_ context.Context, p idtoken.Provider, raw string) (idtoken.Claims, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if slices.Contains(f.Disabled, p) {
		return idtoken.Claims{}, idtoken.ErrDisabled
	}
	e, ok := f.tokens[raw]
	if !ok || e.p != p {
		return idtoken.Claims{}, idtoken.ErrInvalid
	}
	return e.c, nil
}
