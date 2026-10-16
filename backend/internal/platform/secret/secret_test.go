package secret_test

import (
	"bytes"
	"encoding/base64"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

func TestNewTokenIs256BitURLSafeAndHashMatches(t *testing.T) {
	plain, hash := secret.NewToken()

	raw, err := base64.RawURLEncoding.DecodeString(plain)
	if err != nil {
		t.Fatalf("token is not unpadded base64url: %v", err)
	}
	if len(raw) != 32 {
		t.Fatalf("token carries %d bytes, want 32", len(raw))
	}
	if !bytes.Equal(hash, secret.Hash(plain)) {
		t.Fatal("returned hash differs from Hash(plain)")
	}
	if len(hash) != 32 {
		t.Fatalf("hash has %d bytes, want 32 (SHA-256)", len(hash))
	}
}

func TestNewTokenIsRandom(t *testing.T) {
	a, _ := secret.NewToken()
	b, _ := secret.NewToken()
	if a == b {
		t.Fatal("two tokens are equal")
	}
}
