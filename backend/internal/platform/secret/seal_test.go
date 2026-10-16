package secret_test

import (
	"bytes"
	"errors"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/secret"
)

func TestSealOpensOnlyUnderItsKeyAndData(t *testing.T) {
	key := bytes.Repeat([]byte{1}, secret.KeySize)
	other := bytes.Repeat([]byte{2}, secret.KeySize)
	ad := []byte("00000000-0000-0000-0000-000000000001")
	const plain = "JBSWY3DPEHPK3PXP"

	sealed, err := secret.Seal(key, []byte(plain), ad)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := secret.Open(key, sealed, ad); err != nil || string(got) != plain {
		t.Fatalf("round trip: %q %v", got, err)
	}
	if bytes.Contains(sealed, []byte(plain)) {
		t.Fatal("the plaintext shows in the sealed value")
	}
	again, err := secret.Seal(key, []byte(plain), ad)
	if err != nil || bytes.Equal(sealed, again) {
		t.Fatal("two seals of one plaintext must differ: the nonce is random")
	}

	tampered := bytes.Clone(sealed)
	tampered[len(tampered)-1] ^= 1
	for name, open := range map[string]func() ([]byte, error){
		"another key": func() ([]byte, error) { return secret.Open(other, sealed, ad) },
		"another account": func() ([]byte, error) {
			return secret.Open(key, sealed, []byte("00000000-0000-0000-0000-000000000002"))
		},
		"one byte flipped": func() ([]byte, error) { return secret.Open(key, tampered, ad) },
		"truncated":        func() ([]byte, error) { return secret.Open(key, sealed[:5], ad) },
	} {
		if _, err := open(); !errors.Is(err, secret.ErrSealed) {
			t.Errorf("%s: %v, want ErrSealed", name, err)
		}
	}
	if _, err := secret.Seal(key[:16], []byte(plain), ad); !errors.Is(err, secret.ErrKey) {
		t.Fatalf("a 16-byte key: %v, want ErrKey", err)
	}
	if _, err := secret.Open(key[:16], sealed, ad); !errors.Is(err, secret.ErrKey) {
		t.Fatalf("open with a 16-byte key: %v, want ErrKey", err)
	}
}
