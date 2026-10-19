package httpapi

import (
	"context"
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/accesslog"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/clientip"
)

// AccessRecorder keeps the record of each use of the service that the law
// asks for: who (an account or a linked device), from which address and
// port, and when.
type AccessRecorder interface {
	Record(ctx context.Context, e accesslog.Entry) error
}

// recordAccess notes that the request used the service. It never fails
// the request, and a failure is logged without the address: the address
// is personal data the log must not carry.
func (s *Server) recordAccess(r *http.Request, e accesslog.Entry) {
	if s.Access == nil {
		return
	}
	e.IP = s.clientIP(r)
	e.Port = clientip.Port(r.RemoteAddr, r.Header.Get("X-Real-Port"), s.TrustedProxies)
	if err := s.Access.Record(r.Context(), e); err != nil {
		s.Log.Warn("access log: record failed", "err", err)
	}
}
