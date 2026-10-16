// Package appleid revokes a Sign in with Apple authorization when the
// account behind it is erased (App Store Review Guideline 5.1.1(v)).
// It exchanges a fresh authorization code for its refresh
// token and revokes that token at once; nothing is stored.
package appleid

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	defaultBaseURL = "https://appleid.apple.com"
	audience       = "https://appleid.apple.com"
	secretLifetime = 5 * time.Minute
	callTimeout    = 10 * time.Second
)

// ErrInvalidGrant means Apple rejected the authorization code: expired,
// used, or issued to another client.
var ErrInvalidGrant = errors.New("appleid: authorization code rejected")

// statusError is Apple's answer outside 2xx; it never carries the body.
type statusError struct {
	op     string
	status int
}

func (e *statusError) Error() string { return fmt.Sprintf("appleid: %s answered %d", e.op, e.status) }

// Class names a failure for the logs, never its text.
func Class(err error) string {
	var se *statusError
	if errors.As(err, &se) {
		if se.status >= 500 {
			return "apple 5xx"
		}
		return "apple 4xx"
	}
	if errors.Is(err, context.DeadlineExceeded) {
		return "timeout"
	}
	var ne net.Error
	if errors.As(err, &ne) && ne.Timeout() {
		return "timeout"
	}
	return "network"
}

// ParseKey reads the Sign in with Apple key (.p8): a P-256 PKCS#8 PEM.
// Literal "\n" sequences, as a one-line environment value carries them,
// are read as newlines. Errors never quote the input.
func ParseKey(pemText string) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode([]byte(strings.ReplaceAll(pemText, `\n`, "\n")))
	if block == nil || block.Type != "PRIVATE KEY" {
		return nil, errors.New("appleid: key is not a PKCS#8 PEM")
	}
	k, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, errors.New("appleid: key does not parse as PKCS#8")
	}
	ec, ok := k.(*ecdsa.PrivateKey)
	if !ok || ec.Curve != elliptic.P256() {
		return nil, errors.New("appleid: key is not a P-256 key")
	}
	return ec, nil
}

type Client struct {
	HTTP    *http.Client
	BaseURL string // empty: Apple's
	TeamID  string
	KeyID   string
	Key     *ecdsa.PrivateKey
	Now     func() time.Time
}

// Revoke exchanges code for its refresh token under clientID (the
// identity token's audience: the bundle ID or the Services ID), then
// revokes that token. redirectURI is the one the code was issued to by
// Apple's web flow, which Apple requires again in the exchange; empty for
// a native code.
func (c *Client) Revoke(ctx context.Context, clientID, code, redirectURI string) error {
	secret, err := c.clientSecret(clientID)
	if err != nil {
		return err
	}
	var tok struct {
		RefreshToken string `json:"refresh_token"`
		Error        string `json:"error"`
	}
	form := url.Values{
		"client_id": {clientID}, "client_secret": {secret},
		"code": {code}, "grant_type": {"authorization_code"},
	}
	if redirectURI != "" {
		form.Set("redirect_uri", redirectURI)
	}
	status, err := c.post(ctx, "/auth/token", form, &tok)
	if err != nil {
		return err
	}
	if status == http.StatusBadRequest && tok.Error == "invalid_grant" {
		return ErrInvalidGrant
	}
	if status/100 != 2 {
		return &statusError{"token", status}
	}
	if tok.RefreshToken == "" {
		return errors.New("appleid: token answer without a refresh token")
	}
	status, err = c.post(ctx, "/auth/revoke", url.Values{
		"client_id": {clientID}, "client_secret": {secret},
		"token": {tok.RefreshToken}, "token_type_hint": {"refresh_token"},
	}, nil)
	if err != nil {
		return err
	}
	if status/100 != 2 {
		return &statusError{"revoke", status}
	}
	return nil
}

// post sends a form and decodes a JSON answer into out when given; a body
// that does not decode is ignored (the status decides).
func (c *Client) post(ctx context.Context, path string, form url.Values, out any) (int, error) {
	ctx, cancel := context.WithTimeout(ctx, callTimeout)
	defer cancel()
	base := c.BaseURL
	if base == "" {
		base = defaultBaseURL
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, base+path, strings.NewReader(form.Encode()))
	if err != nil {
		return 0, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("Accept", "application/json")
	res, err := c.HTTP.Do(req)
	if err != nil {
		return 0, err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	if out != nil {
		_ = json.Unmarshal(body, out)
	}
	return res.StatusCode, nil
}

// clientSecret is the ES256 JWT Apple asks of a client (Client secret),
// signed per use.
func (c *Client) clientSecret(clientID string) (string, error) {
	now := c.Now()
	enc := func(v any) string {
		b, _ := json.Marshal(v) // maps of strings and numbers always encode
		return base64.RawURLEncoding.EncodeToString(b)
	}
	signing := enc(map[string]string{"alg": "ES256", "kid": c.KeyID}) + "." + enc(map[string]any{
		"iss": c.TeamID, "iat": now.Unix(), "exp": now.Add(secretLifetime).Unix(),
		"aud": audience, "sub": clientID,
	})
	h := sha256.Sum256([]byte(signing))
	r, s, err := ecdsa.Sign(rand.Reader, c.Key, h[:])
	if err != nil {
		return "", err
	}
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])
	return signing + "." + base64.RawURLEncoding.EncodeToString(sig), nil
}
