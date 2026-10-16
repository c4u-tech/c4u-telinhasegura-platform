package identity_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
)

func TestDefaultHashUsesOWASPArgon2idParameters(t *testing.T) {
	h := identity.HashPassword("a perfectly long passphrase", identity.DefaultHashParams)
	if !strings.HasPrefix(h, "$argon2id$v=19$m=19456,t=2,p=1$") {
		t.Fatalf("hash %q does not carry the production parameters", h)
	}
	salt := strings.Split(h, "$")[4]
	if len(salt) != 22 { // 16 bytes, unpadded base64
		t.Fatalf("salt %q is not 16 bytes", salt)
	}
}

func TestVerifyPassword(t *testing.T) {
	cheap := identity.HashParams{Memory: 64, Time: 1, Threads: 1}
	h := identity.HashPassword("right password here", cheap)

	if ok, err := identity.VerifyPassword("right password here", h); err != nil || !ok {
		t.Fatalf("right password: ok=%v err=%v", ok, err)
	}
	if ok, err := identity.VerifyPassword("wrong password here", h); err != nil || ok {
		t.Fatalf("wrong password: ok=%v err=%v", ok, err)
	}
	if h == identity.HashPassword("right password here", cheap) {
		t.Fatal("two hashes of one password share a salt")
	}
}

func TestVerifyPasswordRejectsMalformedHashes(t *testing.T) {
	for _, bad := range []string{"", "$argon2i$v=19$m=1,t=1,p=1$AA$AA", "$argon2id$v=19$garbage$AA$AA"} {
		if _, err := identity.VerifyPassword("x", bad); !errors.Is(err, identity.ErrMalformedHash) {
			t.Errorf("%q: got %v, want ErrMalformedHash", bad, err)
		}
	}
}
