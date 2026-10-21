package httpapi

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// problem is an RFC 9457 body; code is the stable member clients switch on.
type problem struct {
	Type       string   `json:"type"`
	Title      string   `json:"title"`
	Status     int      `json:"status"`
	Code       string   `json:"code"`
	Reasons    []string `json:"reasons,omitempty"`
	RetryAfter int      `json:"retry_after,omitempty"` // seconds, mirrors the header
	Ticket     string   `json:"ticket,omitempty"`      // signup_required, link_required
	Email      string   `json:"email,omitempty"`       // signup_required, link_required
	Options    []string `json:"options,omitempty"`     // link_required
	Reason     string   `json:"reason,omitempty"`      // video_refused, time_up, pack_invalid
}

func newProblem(status int, code string) problem {
	return problem{Type: "urn:telinhasegura:problem:" + code, Title: http.StatusText(status), Status: status, Code: code}
}

func writeProblem(w http.ResponseWriter, p problem) {
	w.Header().Set("Content-Type", "application/problem+json")
	if p.RetryAfter > 0 {
		w.Header().Set("Retry-After", strconv.Itoa(p.RetryAfter))
	}
	w.WriteHeader(p.Status)
	_ = json.NewEncoder(w).Encode(p)
}

// familyProblems maps the family module's sentinels to their status and
// code.
var familyProblems = []struct {
	err    error
	status int
	code   string
}{
	{family.ErrValidation, http.StatusUnprocessableEntity, "validation"},
	{family.ErrNotFound, http.StatusNotFound, "not_found"},
	{family.ErrInvalidToken, http.StatusBadRequest, "invalid_token"},
	{family.ErrEmailUnverified, http.StatusForbidden, "email_unverified"},
	{family.ErrAlreadyInFamily, http.StatusConflict, "already_in_family"},
	{family.ErrNoFamily, http.StatusNotFound, "no_family"},
	{family.ErrNotOwner, http.StatusForbidden, "not_owner"},
	{family.ErrOwnerMustTransfer, http.StatusConflict, "owner_must_transfer"},
	{family.ErrLimitReached, http.StatusConflict, "limit_reached"},
	{family.ErrPolicyOutdated, http.StatusConflict, "policy_outdated"},
	{family.ErrInvitationEmailMismatch, http.StatusForbidden, "invitation_email_mismatch"},
	{family.ErrAlreadyMember, http.StatusConflict, "already_member"},
	{family.ErrInvitationUnavailable, http.StatusNotFound, "invitation_unavailable"},
	{family.ErrOtherGuardians, http.StatusForbidden, "account_suspended"}, // only DeleteAsSoleGuardian returns it
}

// parentalProblems maps the parental module's sentinels to their status
// and code.
var parentalProblems = []struct {
	err    error
	status int
	code   string
}{
	{parental.ErrValidation, http.StatusUnprocessableEntity, "validation"},
	{parental.ErrWeakPIN, http.StatusUnprocessableEntity, "weak_pin"},
	{parental.ErrNoFamily, http.StatusNotFound, "no_family"},
	{parental.ErrNotFound, http.StatusNotFound, "not_found"},
	{parental.ErrPINNotSet, http.StatusConflict, "pin_not_set"},
	{parental.ErrInvalidPIN, http.StatusForbidden, "invalid_pin"},
	{parental.ErrInvalidCode, http.StatusBadRequest, "invalid_token"},
	{parental.ErrLimitReached, http.StatusConflict, "limit_reached"},
	{parental.ErrProfileGone, http.StatusGone, "profile_gone"},
	{parental.ErrUnauthenticated, http.StatusUnauthorized, "unauthenticated"},
	{parental.ErrNotChild, http.StatusForbidden, "not_child"},
	{parental.ErrConsentRequired, http.StatusForbidden, "consent_required"},
}

// staffProblems maps the staff module's sentinels to their status and code.
// curation.ErrNotCurator is staff.ErrNotCurator.
var staffProblems = []struct {
	err    error
	status int
	code   string
}{
	{staff.ErrNotCurator, http.StatusForbidden, "not_curator"},
	{staff.ErrNotAdmin, http.StatusForbidden, "not_admin"},
	{staff.ErrNotModerator, http.StatusForbidden, "not_moderator"},
	{staff.ErrValidation, http.StatusUnprocessableEntity, "validation"},
	{staff.ErrNotFound, http.StatusNotFound, "not_found"},
	{staff.ErrAccountNotFound, http.StatusNotFound, "account_not_found"},
	{staff.ErrEmailUnverified, http.StatusConflict, "email_unverified"},
	{staff.ErrAlreadyHasRole, http.StatusConflict, "already_has_role"},
	{staff.ErrReasonRequired, http.StatusUnprocessableEntity, "reason_required"},
	{staff.ErrSelfAppointment, http.StatusForbidden, "self_appointment"},
	{staff.ErrAdminCLIOnly, http.StatusForbidden, "admin_cli_only"},
	{staff.ErrNotStaff, http.StatusForbidden, "not_staff"},
	{staff.ErrMFAUnavailable, http.StatusServiceUnavailable, "mfa_unavailable"},
	{staff.ErrMFAAlreadyEnrolled, http.StatusConflict, "mfa_already_enrolled"},
	{staff.ErrMFANotPending, http.StatusConflict, "mfa_not_pending"},
	{staff.ErrMFANotEnrolled, http.StatusConflict, "mfa_not_enrolled"},
	{staff.ErrMFACodeInvalid, http.StatusUnprocessableEntity, "mfa_code_invalid"},
	{staff.ErrMFAEnrollmentRequired, http.StatusForbidden, "mfa_enrollment_required"},
	{staff.ErrElevationRequired, http.StatusForbidden, "elevation_required"},
	{staff.ErrSelfAction, http.StatusForbidden, "self_action"},
	{staff.ErrDeviceNotFound, http.StatusNotFound, "device_not_found"},
	{staff.ErrAccountSuspended, http.StatusConflict, "account_suspended"},
	{staff.ErrSubjectIsAdmin, http.StatusForbidden, "subject_is_admin"},
	{staff.ErrAlreadySuspended, http.StatusConflict, "already_suspended"},
	{staff.ErrNotSuspended, http.StatusConflict, "not_suspended"},
}

// curationProblems maps the curation module's sentinels to their status
// and code.
var curationProblems = []struct {
	err    error
	status int
	code   string
}{
	{curation.ErrValidation, http.StatusUnprocessableEntity, "validation"},
	{curation.ErrNotFound, http.StatusNotFound, "not_found"},
	{curation.ErrDeclarationRequired, http.StatusForbidden, "declaration_required"},
	{curation.ErrDeclarationOutdated, http.StatusConflict, "declaration_outdated"},
	{curation.ErrInvalidLink, http.StatusUnprocessableEntity, "invalid_link"},
	{curation.ErrSourceUnavailable, http.StatusServiceUnavailable, "video_source_unavailable"},
	{curation.ErrNotReviewable, http.StatusConflict, "not_reviewable"},
	{curation.ErrAlreadyReviewed, http.StatusConflict, "already_reviewed"},
	{curation.ErrOwnSuggestion, http.StatusForbidden, "own_suggestion"},
	{curation.ErrOwnComposition, http.StatusForbidden, "own_composition"},
	{curation.ErrStateConflict, http.StatusConflict, "state_conflict"},
	{curation.ErrAlreadyAudited, http.StatusConflict, "already_audited"},
	{curation.ErrOwnReview, http.StatusConflict, "own_review"},
	{curation.ErrVideoNotAllowed, http.StatusForbidden, "video_not_allowed"},
	{curation.ErrProfileGone, http.StatusGone, "profile_gone"},
	{curation.ErrThumbnailUnavailable, http.StatusServiceUnavailable, "thumbnail_unavailable"},
	{curation.ErrChecklistOutdated, http.StatusConflict, "checklist_outdated"},
	{curation.ErrChecklistRefuses, http.StatusUnprocessableEntity, "checklist_refuses"},
	{curation.ErrChecklistBand, http.StatusUnprocessableEntity, "checklist_band"},
	{curation.ErrConflictOfInterest, http.StatusConflict, "conflict_of_interest"},
}

// privacyProblems maps the privacy module's sentinels to their status
// and code.
var privacyProblems = []struct {
	err    error
	status int
	code   string
}{
	{privacy.ErrOwnerMustTransfer, http.StatusConflict, "owner_must_transfer"},
	{privacy.ErrAccountGone, http.StatusUnauthorized, "unauthenticated"},
	{privacy.ErrAppleReauthRequired, http.StatusUnprocessableEntity, "apple_reauthorization_required"},
	{privacy.ErrAppleIdentityMismatch, http.StatusForbidden, "apple_identity_mismatch"},
	{privacy.ErrAppleAuthorizationInvalid, http.StatusUnprocessableEntity, "apple_authorization_invalid"},
}

// screentimeProblems maps the screentime module's sentinels to their
// status and code.
var screentimeProblems = []struct {
	err    error
	status int
	code   string
}{
	{screentime.ErrValidation, http.StatusUnprocessableEntity, "validation"},
	{screentime.ErrNotFound, http.StatusNotFound, "not_found"},
	{screentime.ErrProfileGone, http.StatusGone, "profile_gone"},
	{screentime.ErrPlayClosed, http.StatusConflict, "play_closed"},
	{screentime.ErrOverCap, http.StatusUnprocessableEntity, "over_cap"},
}

// fail maps a domain error to its problem. Unknown errors are logged and
// answered as a generic 500. Family errors are mapped first, through
// familyProblems.
func (s *Server) fail(w http.ResponseWriter, err error) {
	var famThrottled *family.ThrottledError
	if errors.As(err, &famThrottled) {
		writeRateLimited(w, famThrottled.RetryAfter)
		return
	}
	var parThrottled *parental.ThrottledError
	if errors.As(err, &parThrottled) {
		writeRateLimited(w, parThrottled.RetryAfter)
		return
	}
	var privThrottled *privacy.ThrottledError
	if errors.As(err, &privThrottled) {
		writeRateLimited(w, privThrottled.RetryAfter)
		return
	}
	var refused *curation.RefusedError
	if errors.As(err, &refused) {
		p := newProblem(http.StatusUnprocessableEntity, "video_refused")
		p.Reason = refused.Reason
		writeProblem(w, p)
		return
	}
	var invalid *curation.PackInvalidError
	if errors.As(err, &invalid) {
		p := newProblem(http.StatusUnprocessableEntity, "pack_invalid")
		p.Reason = invalid.Reason
		writeProblem(w, p)
		return
	}
	var curThrottled *curation.ThrottledError
	if errors.As(err, &curThrottled) {
		writeRateLimited(w, curThrottled.RetryAfter)
		return
	}
	var staffThrottled *staff.ThrottledError
	if errors.As(err, &staffThrottled) {
		writeRateLimited(w, staffThrottled.RetryAfter)
		return
	}
	var timeUp *screentime.TimeUpError
	if errors.As(err, &timeUp) {
		p := newProblem(http.StatusForbidden, "time_up")
		p.Reason = timeUp.Reason
		writeProblem(w, p)
		return
	}
	var stThrottled *screentime.ThrottledError
	if errors.As(err, &stThrottled) {
		writeRateLimited(w, stThrottled.RetryAfter)
		return
	}
	for _, sp := range screentimeProblems {
		if errors.Is(err, sp.err) {
			writeProblem(w, newProblem(sp.status, sp.code))
			return
		}
	}
	for _, sp := range staffProblems {
		if errors.Is(err, sp.err) {
			writeProblem(w, newProblem(sp.status, sp.code))
			return
		}
	}
	for _, cp := range curationProblems {
		if errors.Is(err, cp.err) {
			writeProblem(w, newProblem(cp.status, cp.code))
			return
		}
	}
	for _, pp := range privacyProblems {
		if errors.Is(err, pp.err) {
			writeProblem(w, newProblem(pp.status, pp.code))
			return
		}
	}
	for _, pp := range parentalProblems {
		if errors.Is(err, pp.err) {
			writeProblem(w, newProblem(pp.status, pp.code))
			return
		}
	}
	for _, fp := range familyProblems {
		if errors.Is(err, fp.err) {
			writeProblem(w, newProblem(fp.status, fp.code))
			return
		}
	}
	var weak *identity.WeakPasswordError
	var throttled *identity.ThrottledError
	var confirm *identity.ConfirmationRequiredError
	switch {
	case errors.As(err, &weak):
		p := newProblem(http.StatusUnprocessableEntity, "weak_password")
		p.Reasons = weak.Reasons
		writeProblem(w, p)
	case errors.As(err, &confirm):
		p := newProblem(http.StatusConflict, confirm.Code)
		p.Ticket, p.Email, p.Options = confirm.Ticket, confirm.Email, confirm.Options
		writeProblem(w, p)
	case errors.Is(err, identity.ErrProviderEmailUnverified):
		writeProblem(w, newProblem(http.StatusUnprocessableEntity, "provider_email_unverified"))
	case errors.Is(err, identity.ErrTermsOutdated):
		writeProblem(w, newProblem(http.StatusConflict, "terms_outdated"))
	case errors.Is(err, identity.ErrIdentityConflict):
		writeProblem(w, newProblem(http.StatusConflict, "identity_conflict"))
	case errors.Is(err, errUnsupportedMedia):
		writeProblem(w, newProblem(http.StatusUnsupportedMediaType, "validation"))
	case errors.Is(err, errBadBody), errors.Is(err, identity.ErrValidation):
		writeProblem(w, newProblem(http.StatusUnprocessableEntity, "validation"))
	case errors.Is(err, identity.ErrInvalidToken):
		writeProblem(w, newProblem(http.StatusBadRequest, "invalid_token"))
	case errors.As(err, &throttled):
		writeRateLimited(w, throttled.RetryAfter)
	case errors.Is(err, identity.ErrInvalidCredentials):
		writeProblem(w, newProblem(http.StatusUnauthorized, "invalid_credentials"))
	case errors.Is(err, session.ErrUnauthenticated):
		writeProblem(w, newProblem(http.StatusUnauthorized, "unauthenticated"))
	case errors.Is(err, session.ErrInvalidToken):
		writeProblem(w, newProblem(http.StatusUnauthorized, "invalid_token"))
	case errors.Is(err, session.ErrReauthRequired):
		writeProblem(w, newProblem(http.StatusForbidden, "reauth_required"))
	case errors.Is(err, errKidMode):
		writeProblem(w, newProblem(http.StatusForbidden, "kid_mode"))
	case errors.Is(err, errSuspended):
		writeProblem(w, newProblem(http.StatusForbidden, "account_suspended"))
	case errors.Is(err, errCSRF):
		writeProblem(w, newProblem(http.StatusForbidden, "csrf_failed"))
	case errors.Is(err, session.ErrNotFound):
		writeProblem(w, newProblem(http.StatusNotFound, "not_found"))
	default:
		s.Log.Error("request failed", "err", err)
		writeProblem(w, newProblem(http.StatusInternalServerError, "internal"))
	}
}
