package httpapi

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// The account directory's routes. All are of kind
// admin; the support actions also need a fresh re-authentication.

type sheetFamilyOut struct {
	Role    string `json:"role"`
	Minors  int    `json:"minors"`
	Devices int    `json:"devices"`
}

type sheetDeviceOut struct {
	ID         string    `json:"id"`
	LinkedAt   time.Time `json:"linked_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

type sheetSessionOut struct {
	Client     string    `json:"client"`
	CreatedAt  time.Time `json:"created_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

type suspensionOut struct {
	Since  time.Time `json:"since"`
	Reason string    `json:"reason"`
}

type auditActionOut struct {
	ID                 int64           `json:"id"`
	OccurredAt         time.Time       `json:"occurred_at"`
	Event              string          `json:"event"`
	ActorID            string          `json:"actor_id"`
	ActorEmail         *string         `json:"actor_email"`
	ActorRole          string          `json:"actor_role"`
	SubjectKind        *string         `json:"subject_kind"`
	SubjectID          *string         `json:"subject_id"`
	SubjectEmailMasked *string         `json:"subject_email_masked"`
	Reason             *string         `json:"reason"`
	Metadata           json.RawMessage `json:"metadata"` // as stored; null for none
}

type accountSheetOut struct {
	AccountID     string            `json:"account_id"`
	EmailMasked   string            `json:"email_masked"`
	EmailVerified bool              `json:"email_verified"`
	CreatedAt     time.Time         `json:"created_at"`
	Providers     []string          `json:"providers"`
	Roles         []string          `json:"roles"`
	MFAEnrolled   bool              `json:"mfa_enrolled"`
	Suspension    *suspensionOut    `json:"suspension"` // null unless suspended
	Family        *sheetFamilyOut   `json:"family"`
	Devices       []sheetDeviceOut  `json:"devices"`
	Sessions      []sheetSessionOut `json:"sessions"`
	Actions       []auditActionOut  `json:"actions"`
}

func auditActionsBody(list []staff.AuditEntry) []auditActionOut {
	out := make([]auditActionOut, 0, len(list))
	for _, e := range list {
		out = append(out, auditActionOut{ID: e.ID, OccurredAt: e.OccurredAt.UTC(), Event: e.Event, ActorID: e.ActorID,
			ActorEmail: orNull(e.ActorEmail), ActorRole: e.ActorRole, SubjectKind: orNull(e.SubjectKind),
			SubjectID: orNull(e.SubjectID), SubjectEmailMasked: orNull(e.SubjectEmailMasked), Reason: orNull(e.Reason),
			Metadata: e.Metadata})
	}
	return out
}

// sheetBody writes every list as [] when empty and family as null
// without one (AccountSheet).
func sheetBody(sh staff.AccountSheet) accountSheetOut {
	out := accountSheetOut{AccountID: sh.AccountID, EmailMasked: sh.EmailMasked, EmailVerified: sh.EmailVerified,
		CreatedAt: sh.CreatedAt.UTC(), Providers: sh.Providers, Roles: make([]string, 0, len(sh.Roles)), MFAEnrolled: sh.MFAEnrolled,
		Devices: make([]sheetDeviceOut, 0, len(sh.Devices)), Sessions: make([]sheetSessionOut, 0, len(sh.Sessions)),
		Actions: auditActionsBody(sh.Actions)}
	if out.Providers == nil {
		out.Providers = []string{}
	}
	for _, r := range sh.Roles {
		out.Roles = append(out.Roles, string(r))
	}
	if f := sh.Family; f != nil {
		out.Family = &sheetFamilyOut{Role: string(f.Role), Minors: f.Minors, Devices: f.Devices}
	}
	for _, d := range sh.Devices {
		out.Devices = append(out.Devices, sheetDeviceOut{ID: d.ID, LinkedAt: d.LinkedAt.UTC(), LastSeenAt: d.LastSeenAt.UTC()})
	}
	for _, x := range sh.Sessions {
		out.Sessions = append(out.Sessions, sheetSessionOut{Client: string(x.Client), CreatedAt: x.CreatedAt.UTC(), LastSeenAt: x.LastSeenAt.UTC()})
	}
	if x := sh.Suspension; x != nil {
		out.Suspension = &suspensionOut{Since: x.Since.UTC(), Reason: x.Reason}
	}
	return out
}

func (s *Server) writeSheet(w http.ResponseWriter, sh staff.AccountSheet, err error) {
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, sheetBody(sh))
}

// lookupAccount takes the email or the id in the body, never in the URL,
// so neither reaches an access log.
func (s *Server) lookupAccount(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email     *string `json:"email"`
		AccountID *string `json:"account_id"`
		Reason    string  `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	sh, err := s.Staff.Lookup(r.Context(), current(r).AccountID,
		staff.LookupInput{Email: in.Email, AccountID: in.AccountID, Reason: in.Reason})
	s.writeSheet(w, sh, err)
}

// supportReason decodes a support action's body; false once it has
// answered a malformed one.
func (s *Server) supportReason(w http.ResponseWriter, r *http.Request) (string, bool) {
	var in struct {
		Reason string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return "", false
	}
	return in.Reason, true
}

func (s *Server) revokeAccountSessions(w http.ResponseWriter, r *http.Request) {
	reason, ok := s.supportReason(w, r)
	if !ok {
		return
	}
	sh, err := s.Staff.RevokeAccountSessions(r.Context(), current(r).AccountID, r.PathValue("account_id"), reason)
	s.writeSheet(w, sh, err)
}

func (s *Server) unlinkAccountDevice(w http.ResponseWriter, r *http.Request) {
	reason, ok := s.supportReason(w, r)
	if !ok {
		return
	}
	sh, err := s.Staff.UnlinkAccountDevice(r.Context(), current(r).AccountID, r.PathValue("account_id"), r.PathValue("device_id"), reason)
	s.writeSheet(w, sh, err)
}

func (s *Server) sendAccountPasswordReset(w http.ResponseWriter, r *http.Request) {
	reason, ok := s.supportReason(w, r)
	if !ok {
		return
	}
	sh, err := s.Staff.SendAccountPasswordReset(r.Context(), current(r).AccountID, r.PathValue("account_id"), reason)
	s.writeSheet(w, sh, err)
}
