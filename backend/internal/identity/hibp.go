package identity

import (
	"bufio"
	"context"
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

const HIBPBaseURL = "https://api.pwnedpasswords.com/range/"

var ErrBreachCheckUnavailable = errors.New("identity: breached-password check unavailable")

// HIBP queries Have I Been Pwned's k-anonymity range API: only the first
// five hex characters of the SHA-1 leave the server.
type HIBP struct {
	Client  *http.Client
	BaseURL string
}

func (h HIBP) IsBreached(ctx context.Context, password string) (bool, error) {
	sum := sha1.Sum([]byte(password))
	digest := strings.ToUpper(hex.EncodeToString(sum[:]))
	prefix, suffix := digest[:5], digest[5:]

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, h.BaseURL+prefix, nil)
	if err != nil {
		return false, ErrBreachCheckUnavailable
	}
	req.Header.Set("Add-Padding", "true")
	resp, err := h.Client.Do(req)
	if err != nil {
		var ue *url.Error
		if errors.As(err, &ue) {
			err = ue.Err // drop the URL: it carries the hash prefix
		}
		return false, errors.Join(ErrBreachCheckUnavailable, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("%w: status %d", ErrBreachCheckUnavailable, resp.StatusCode)
	}
	sc := bufio.NewScanner(resp.Body)
	for sc.Scan() {
		s, count, ok := strings.Cut(strings.TrimSpace(sc.Text()), ":")
		if ok && s == suffix && count != "0" {
			return true, nil
		}
	}
	if err := sc.Err(); err != nil {
		return false, errors.Join(ErrBreachCheckUnavailable, err)
	}
	return false, nil
}
