package httpapi

import (
	"errors"
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
)

type memberOut struct {
	AccountID string    `json:"account_id"`
	Email     string    `json:"email"`
	Role      string    `json:"role"`
	JoinedAt  time.Time `json:"joined_at"`
}

type minorOut struct {
	ID             string    `json:"id"`
	Nickname       string    `json:"nickname"`
	Avatar         string    `json:"avatar"`
	AgeBand        string    `json:"age_band"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
	ConsentCurrent bool      `json:"consent_current"`
}

type invitationOut struct {
	ID        string    `json:"id"`
	Email     string    `json:"email"`
	ExpiresAt time.Time `json:"expires_at"`
}

// familyOut is the Family body: invitations is present for the owner
// only, hence the pointer.
type familyOut struct {
	ID                 string           `json:"id"`
	Role               string           `json:"role"`
	Members            []memberOut      `json:"members"`
	Minors             []minorOut       `json:"minors"`
	PendingInvitations int              `json:"pending_invitations"`
	Invitations        *[]invitationOut `json:"invitations,omitempty"`
}

func minorBody(m family.Minor) minorOut {
	return minorOut{m.ID, m.Nickname, m.Avatar, string(m.AgeBand), m.CreatedAt.UTC(), m.UpdatedAt.UTC(), m.ConsentCurrent}
}

func invitationBody(i family.Invitation) invitationOut {
	return invitationOut{i.ID, i.Email, i.ExpiresAt.UTC()}
}

func familyBody(f family.Family) familyOut {
	out := familyOut{
		ID:                 f.ID,
		Role:               string(f.Role),
		Members:            make([]memberOut, 0, len(f.Members)),
		Minors:             make([]minorOut, 0, len(f.Minors)),
		PendingInvitations: f.PendingInvitations,
	}
	for _, m := range f.Members {
		out.Members = append(out.Members, memberOut{m.AccountID, m.Email, string(m.Role), m.JoinedAt.UTC()})
	}
	for _, m := range f.Minors {
		out.Minors = append(out.Minors, minorBody(m))
	}
	if f.Role == family.Owner {
		invs := make([]invitationOut, 0, len(f.Invitations))
		for _, i := range f.Invitations {
			invs = append(invs, invitationBody(i))
		}
		out.Invitations = &invs
	}
	return out
}

func (s *Server) createFamily(w http.ResponseWriter, r *http.Request) {
	f, err := s.Family.Create(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, familyBody(f))
}

func (s *Server) getFamily(w http.ResponseWriter, r *http.Request) {
	f, err := s.Family.Get(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, familyBody(f))
}

func (s *Server) invite(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email string `json:"email"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	inv, err := s.Family.Invite(r.Context(), current(r).AccountID, in.Email)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, invitationBody(inv))
}

func (s *Server) revokeInvitation(w http.ResponseWriter, r *http.Request) {
	if err := s.Family.RevokeInvitation(r.Context(), current(r).AccountID, r.PathValue("id")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type tokenIn struct {
	Token string `json:"token"`
}

func (s *Server) lookupInvitation(w http.ResponseWriter, r *http.Request) {
	var in tokenIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	p, err := s.Family.LookupInvitation(r.Context(), current(r).AccountID, in.Token)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"inviter_email": p.InviterEmail,
		"invited_email": p.InvitedEmail,
		"expires_at":    p.ExpiresAt.UTC(),
	})
}

func (s *Server) acceptInvitation(w http.ResponseWriter, r *http.Request) {
	var in tokenIn
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	f, err := s.Family.AcceptInvitation(r.Context(), current(r).AccountID, in.Token)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, familyBody(f))
}

type receivedOut struct {
	ID           string    `json:"id"`
	InviterEmail string    `json:"inviter_email"`
	ExpiresAt    time.Time `json:"expires_at"`
}

func (s *Server) receivedInvitations(w http.ResponseWriter, r *http.Request) {
	invs, err := s.Family.PendingInvitations(r.Context(), current(r).AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	out := make([]receivedOut, 0, len(invs))
	for _, i := range invs {
		out = append(out, receivedOut{i.ID, i.InviterEmail, i.ExpiresAt.UTC()})
	}
	writeJSON(w, http.StatusOK, map[string]any{"invitations": out})
}

func (s *Server) acceptInvitationByID(w http.ResponseWriter, r *http.Request) {
	f, err := s.Family.AcceptInvitationByID(r.Context(), current(r).AccountID, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, familyBody(f))
}

func (s *Server) removeGuardian(w http.ResponseWriter, r *http.Request) {
	if err := s.Family.RemoveGuardian(r.Context(), current(r).AccountID, r.PathValue("account_id")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) leaveFamily(w http.ResponseWriter, r *http.Request) {
	if err := s.Family.Leave(r.Context(), current(r).AccountID); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) transferOwnership(w http.ResponseWriter, r *http.Request) {
	var in struct {
		AccountID string `json:"account_id"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	f, err := s.Family.TransferOwnership(r.Context(), current(r).AccountID, in.AccountID)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, familyBody(f))
}

func (s *Server) createMinor(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Nickname string         `json:"nickname"`
		Avatar   string         `json:"avatar"`
		AgeBand  family.AgeBand `json:"age_band"`
		Consent  *struct {
			PolicyVersion string `json:"policy_version"`
		} `json:"consent"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	var version string
	if in.Consent != nil {
		version = in.Consent.PolicyVersion
	}
	m, err := s.Family.CreateMinor(r.Context(), current(r).AccountID,
		family.MinorInput{Nickname: in.Nickname, Avatar: in.Avatar, AgeBand: in.AgeBand}, version)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, minorBody(m))
}

// grantConsent records the guardian's consent for an existing profile
// under the policy version the app showed.
func (s *Server) grantConsent(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PolicyVersion string `json:"policy_version"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if err := s.Family.GrantConsent(r.Context(), current(r).AccountID, r.PathValue("id"), in.PolicyVersion); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) updateMinor(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Nickname *string         `json:"nickname"`
		Avatar   *string         `json:"avatar"`
		AgeBand  *family.AgeBand `json:"age_band"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	m, err := s.Family.UpdateMinor(r.Context(), current(r).AccountID, r.PathValue("id"),
		family.MinorPatch{Nickname: in.Nickname, Avatar: in.Avatar, AgeBand: in.AgeBand})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, minorBody(m))
}

// deleteFamily is on the suspended allow-list, but a suspended owner
// only deletes a family they are alone in: the family check runs under its lock, the status is read here.
func (s *Server) deleteFamily(w http.ResponseWriter, r *http.Request) {
	id := current(r).AccountID
	del := s.Family.Delete
	switch err := s.refuseSuspended(r.Context(), id); {
	case errors.Is(err, errSuspended):
		del = s.Family.DeleteAsSoleGuardian
	case err != nil:
		s.fail(w, err)
		return
	}
	if err := del(r.Context(), id); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) deleteMinor(w http.ResponseWriter, r *http.Request) {
	if err := s.Family.DeleteMinor(r.Context(), current(r).AccountID, r.PathValue("id")); err != nil {
		s.fail(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
