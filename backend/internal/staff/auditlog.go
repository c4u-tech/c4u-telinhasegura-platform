package staff

import "context"

const auditPageSize = 50

// AuditPage is one page of the staff audit log; NextOffset is nil when
// no row follows.
type AuditPage struct {
	Actions    []AuditEntry
	NextOffset *int
}

// AuditLog pages the staff actions, newest first, by offset. Reading it
// is not audited and needs no reason.
func (s *Service) AuditLog(ctx context.Context, offset int) (AuditPage, error) {
	if offset < 0 {
		return AuditPage{}, ErrValidation
	}
	rows, more, err := s.d.AuditLog.StaffActions(ctx, offset, auditPageSize)
	if err != nil {
		return AuditPage{}, err
	}
	entries, err := s.entries(ctx, rows)
	if err != nil {
		return AuditPage{}, err
	}
	page := AuditPage{Actions: entries}
	if more {
		n := offset + len(rows)
		page.NextOffset = &n
	}
	return page, nil
}
