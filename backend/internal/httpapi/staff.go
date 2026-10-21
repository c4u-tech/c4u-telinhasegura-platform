package httpapi

import (
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

type heldRoleOut struct {
	Role                 string    `json:"role"`
	GrantedAt            time.Time `json:"granted_at"`
	DisplayRole          *string   `json:"display_role,omitempty"`
	VerifiedProfessional *bool     `json:"verified_professional,omitempty"`
}

type staffMemberOut struct {
	AccountID string        `json:"account_id"`
	Email     string        `json:"email"`
	Roles     []heldRoleOut `json:"roles"`
}

// staffMemberBody writes a curator's displayed role and flag on its own
// entry only, and roles as [] once none is left, never null.
func staffMemberBody(m staff.Member) staffMemberOut {
	out := staffMemberOut{AccountID: m.AccountID, Email: m.Email, Roles: make([]heldRoleOut, 0, len(m.Roles))}
	for _, h := range m.Roles {
		r := heldRoleOut{Role: string(h.Role), GrantedAt: h.GrantedAt.UTC()}
		if h.Role == staff.Curator {
			d, v := string(h.DisplayRole), h.VerifiedProfessional
			r.DisplayRole, r.VerifiedProfessional = &d, &v
		}
		out.Roles = append(out.Roles, r)
	}
	return out
}

func (s *Server) listStaff(w http.ResponseWriter, r *http.Request) {
	list, err := s.Staff.Members(r.Context())
	if err != nil {
		s.fail(w, err)
		return
	}
	out := make([]staffMemberOut, 0, len(list))
	for _, m := range list {
		out = append(out, staffMemberBody(m))
	}
	writeJSON(w, http.StatusOK, map[string]any{"staff": out})
}

func (s *Server) grantStaff(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email                string `json:"email"`
		Role                 string `json:"role"`
		DisplayRole          string `json:"display_role"`
		VerifiedProfessional *bool  `json:"verified_professional"`
		Reason               string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	m, err := s.Staff.Grant(r.Context(), current(r).AccountID, staff.GrantInput{Email: in.Email, Role: staff.Role(in.Role),
		DisplayRole: staff.DisplayRole(in.DisplayRole), VerifiedProfessional: in.VerifiedProfessional, Reason: in.Reason})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, staffMemberBody(m))
}

// curatorPatch is a curator's change: a field left nil stays as it is.
func curatorPatch(displayRole *string, verified *bool) staff.CuratorPatch {
	p := staff.CuratorPatch{VerifiedProfessional: verified}
	if displayRole != nil {
		role := staff.DisplayRole(*displayRole)
		p.DisplayRole = &role
	}
	return p
}

func (s *Server) patchStaffCurator(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DisplayRole          *string `json:"display_role"`
		VerifiedProfessional *bool   `json:"verified_professional"`
		Reason               string  `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	m, err := s.Staff.PatchCurator(r.Context(), current(r).AccountID, r.PathValue("account_id"),
		curatorPatch(in.DisplayRole, in.VerifiedProfessional), in.Reason)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, staffMemberBody(m))
}

func (s *Server) revokeStaff(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Reason string `json:"reason"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	m, err := s.Staff.Revoke(r.Context(), current(r).AccountID, r.PathValue("account_id"), staff.Role(r.PathValue("role")), in.Reason)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, staffMemberBody(m))
}
