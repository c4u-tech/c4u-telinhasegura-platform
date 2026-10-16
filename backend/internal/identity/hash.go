package identity

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

type HashParams struct {
	Memory  uint32 // KiB
	Time    uint32
	Threads uint8
}

// DefaultHashParams is the OWASP Password Storage minimum for Argon2id.
var DefaultHashParams = HashParams{Memory: 19456, Time: 2, Threads: 1}

var ErrMalformedHash = errors.New("identity: malformed password hash")

const (
	saltLen = 16
	keyLen  = 32
)

var b64 = base64.RawStdEncoding

// HashPassword returns a PHC string, so parameters can rise later without
// breaking stored hashes.
func HashPassword(password string, p HashParams) string {
	salt := make([]byte, saltLen)
	_, _ = rand.Read(salt)
	key := argon2.IDKey([]byte(password), salt, p.Time, p.Memory, p.Threads, keyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, p.Memory, p.Time, p.Threads, b64.EncodeToString(salt), b64.EncodeToString(key))
}

func VerifyPassword(password, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, ErrMalformedHash
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return false, ErrMalformedHash
	}
	var p HashParams
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.Memory, &p.Time, &p.Threads); err != nil {
		return false, ErrMalformedHash
	}
	salt, err := b64.DecodeString(parts[4])
	if err != nil {
		return false, ErrMalformedHash
	}
	key, err := b64.DecodeString(parts[5])
	if err != nil || len(key) == 0 {
		return false, ErrMalformedHash
	}
	got := argon2.IDKey([]byte(password), salt, p.Time, p.Memory, p.Threads, uint32(len(key)))
	return subtle.ConstantTimeCompare(got, key) == 1, nil
}
