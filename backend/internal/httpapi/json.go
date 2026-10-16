package httpapi

import (
	"encoding/json"
	"errors"
	"mime"
	"net/http"
)

const maxBodyBytes = 1 << 20

var (
	errBadBody          = errors.New("httpapi: malformed request body")
	errUnsupportedMedia = errors.New("httpapi: request body must be application/json")
)

// decode reads one JSON object strictly: unknown fields, trailing data and
// oversized bodies are all errBadBody (answered as 422 validation). A body
// not declared as application/json is errUnsupportedMedia (415): a cross-site
// form cannot send that type, so it cannot reach the handlers (login CSRF).
func decode(w http.ResponseWriter, r *http.Request, dst any) error {
	if mt, _, err := mime.ParseMediaType(r.Header.Get("Content-Type")); err != nil || mt != "application/json" {
		return errUnsupportedMedia
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxBodyBytes))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return errBadBody
	}
	if dec.More() {
		return errBadBody
	}
	return nil
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
