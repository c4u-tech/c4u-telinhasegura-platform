// Package totp computes and checks RFC 6238 time-based one-time
// passwords: HMAC-SHA1, six digits, 30-second steps. It is small enough
// to own, and the RFC's vectors pin it
// (TestCodesMatchTheRFC6238Vectors).
package totp

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"crypto/subtle"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

const (
	Digits      = 6
	Period      = 30 * time.Second
	secretBytes = 20 // RFC 4226 §4 recommends 160 bits
)

var enc = base32.StdEncoding.WithPadding(base32.NoPadding)

// NewSecret is a random secret, base32 without padding, as
// authenticator apps take it.
func NewSecret() string {
	b := make([]byte, secretBytes)
	_, _ = rand.Read(b) // crypto/rand.Read never fails since Go 1.24
	return enc.EncodeToString(b)
}

// Step is the 30-second step t falls in.
func Step(t time.Time) int64 { return t.Unix() / int64(Period/time.Second) }

// Code is the six-digit code of secret at step.
func Code(secret string, step int64) (string, error) {
	key, err := enc.DecodeString(strings.ToUpper(secret))
	if err != nil {
		return "", err
	}
	var msg [8]byte
	binary.BigEndian.PutUint64(msg[:], uint64(step))
	m := hmac.New(sha1.New, key)
	m.Write(msg[:])
	sum := m.Sum(nil)
	off := sum[len(sum)-1] & 0x0f
	bin := binary.BigEndian.Uint32(sum[off:off+4]) & 0x7fffffff
	return fmt.Sprintf("%06d", bin%1_000_000), nil
}

// Verify reports the step, of now's and one either side, whose code is
// code; spaces are ignored, as apps show "287 082". The latest matching
// step wins, so replay protection compares against the strictest step.
func Verify(secret, code string, now time.Time) (int64, bool) {
	code = strings.ReplaceAll(code, " ", "")
	if len(code) != Digits || strings.Trim(code, "0123456789") != "" {
		return 0, false
	}
	cur := Step(now)
	for _, step := range []int64{cur + 1, cur, cur - 1} {
		want, err := Code(secret, step)
		if err != nil {
			return 0, false
		}
		if subtle.ConstantTimeCompare([]byte(want), []byte(code)) == 1 {
			return step, true
		}
	}
	return 0, false
}

// URI is the otpauth:// link an authenticator app enrolls from (the
// Key Uri Format), with every parameter spelled out.
func URI(issuer, account, secret string) string {
	return "otpauth://totp/" + url.PathEscape(issuer) + ":" + url.PathEscape(account) +
		"?secret=" + secret + "&issuer=" + url.PathEscape(issuer) +
		"&algorithm=SHA1&digits=6&period=30"
}
