// Package secret mints the random tokens the API hands out and the
// digests it stores in their place, and seals the few secrets the API
// must read back.
package secret

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
)

// NewToken returns a 256-bit random token, encoded as unpadded base64url
// so it travels in URLs unescaped, and the SHA-256 digest to store.
func NewToken() (plain string, hash []byte) {
	b := make([]byte, 32)
	_, _ = rand.Read(b) // crypto/rand.Read never fails since Go 1.24
	plain = base64.RawURLEncoding.EncodeToString(b)
	return plain, Hash(plain)
}

// Hash is the digest under which a token is stored and looked up.
func Hash(plain string) []byte {
	sum := sha256.Sum256([]byte(plain))
	return sum[:]
}

// KeySize is the length of a sealing key: AES-256.
const KeySize = 32

var (
	ErrKey    = errors.New("secret: a sealing key must be 32 bytes")
	ErrSealed = errors.New("secret: the sealed value is corrupt, or sealed under another key or data")
)

// Seal encrypts plain with AES-256-GCM under key and binds it to ad, so
// a value copied to another row does not open. The
// result is the random nonce followed by the ciphertext.
func Seal(key, plain, ad []byte) ([]byte, error) {
	aead, err := gcm(key)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, aead.NonceSize())
	_, _ = rand.Read(nonce) // crypto/rand.Read never fails since Go 1.24
	return aead.Seal(nonce, nonce, plain, ad), nil
}

// Open reverses Seal. Any other key, other ad or altered byte is
// ErrSealed.
func Open(key, sealed, ad []byte) ([]byte, error) {
	aead, err := gcm(key)
	if err != nil {
		return nil, err
	}
	n := aead.NonceSize()
	if len(sealed) < n+aead.Overhead() {
		return nil, ErrSealed
	}
	plain, err := aead.Open(nil, sealed[:n], sealed[n:], ad)
	if err != nil {
		return nil, ErrSealed
	}
	return plain, nil
}

func gcm(key []byte) (cipher.AEAD, error) {
	if len(key) != KeySize {
		return nil, ErrKey
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}
