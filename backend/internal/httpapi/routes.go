package httpapi

import (
	"net/http"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// RouteKind is the credential a route accepts. It also picks the route's
// middleware, so a route's declared kind is its behavior, and the scope
// tests that walk Routes() cover every route, including later ones.
type RouteKind string

const (
	PublicRoute    RouteKind = "public"    // no credential; per-IP limited
	SessionRoute   RouteKind = "session"   // any session, locked to a child or not
	GuardianRoute  RouteKind = "guardian"  // a session not locked to a child
	ChildRoute     RouteKind = "child"     // a child principal: a locked session or a linked device
	CuratorRoute   RouteKind = "curator"   // a guardian session whose account is a curator
	AdminRoute     RouteKind = "admin"     // a guardian session whose account is an admin
	ModeratorRoute RouteKind = "moderator" // a guardian session whose account is a moderator or an admin
	StaffRoute     RouteKind = "staff"     // a guardian session whose account holds any platform role
)

type Route struct {
	Pattern string
	Kind    RouteKind
	// SuspendedOK puts the route on a suspended account\'s allow-list.
	// Every other session-backed route
	// refuses such an account, a new one included.
	SuspendedOK bool
}

type route struct {
	Route
	h        http.HandlerFunc
	reauth   bool // guardian, admin, moderator, staff: needs a re-authentication within 5 minutes
	elevated bool // staff: needs the session's privileged elevation
	bare     bool // public: outside the per-IP budget (health checks)
	consent  bool // child: refused while the child's consent is not current
}

// Routes lists every registered route with its kind.
func (s *Server) Routes() []Route {
	rs := s.routes()
	out := make([]Route, len(rs))
	for i, r := range rs {
		out[i] = r.Route
	}
	return out
}

// routes is the only place a route is registered.
func (s *Server) routes() []route {
	public := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: PublicRoute}, h: h}
	}
	guardian := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: GuardianRoute}, h: h}
	}
	kid := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: ChildRoute}, h: h}
	}
	// kidConsented is a child route a paused child cannot reach; the
	// unlock and the profile picker stay open so the device can leave it.
	kidConsented := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: ChildRoute}, h: h, consent: true}
	}
	reauthed := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: GuardianRoute}, h: h, reauth: true}
	}
	curator := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: CuratorRoute}, h: h}
	}
	admin := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: AdminRoute}, h: h}
	}
	adminReauthed := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: AdminRoute}, h: h, reauth: true}
	}
	staffRoute := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: StaffRoute}, h: h}
	}
	staffReauthed := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: StaffRoute}, h: h, reauth: true}
	}
	moderator := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: ModeratorRoute}, h: h}
	}
	moderatorReauthed := func(p string, h http.HandlerFunc) route {
		return route{Route: Route{Pattern: p, Kind: ModeratorRoute}, h: h, reauth: true}
	}
	// suspendedOK puts a guardian or session route on a suspended
	// account's allow-list. What stays open is signing out, the
	// re-authentication, the export and the erasure, with an owner's
	// required steps (LGPD art. 18).
	suspendedOK := func(rt route) route {
		rt.SuspendedOK = true
		return rt
	}
	return []route{
		{Route: Route{Pattern: "GET /healthz", Kind: PublicRoute}, h: s.health, bare: true},
		{Route: Route{Pattern: "GET /livez", Kind: PublicRoute}, h: s.live, bare: true},
		public("POST /v1/accounts", s.signUp),
		public("POST /v1/email-verifications", s.resendVerification),
		public("POST /v1/email-verifications/confirm", s.confirmEmail),
		public("POST /v1/sessions", s.signIn),
		public("POST /v1/sessions/provider", s.providerSignIn),
		public("POST /v1/sessions/provider/signup", s.providerSignUp),
		public("POST /v1/sessions/provider/link", s.providerLink),
		public("POST /v1/oauth/apple/callback", s.appleCallback),
		// The refresh token is its own credential, so a session locked to a
		// child keeps refreshing.
		public("POST /v1/session/refresh", s.refresh),
		public("POST /v1/password-resets", s.requestPasswordReset),
		public("POST /v1/password-resets/confirm", s.confirmPasswordReset),
		{Route: Route{Pattern: "GET /v1/session", Kind: SessionRoute, SuspendedOK: true}, h: s.getSession},
		suspendedOK(guardian("DELETE /v1/session", s.signOut)),
		suspendedOK(guardian("POST /v1/session/reauth", s.reauth)),
		suspendedOK(guardian("POST /v1/account/terms", s.acceptTerms)),
		guardian("GET /v1/sessions", s.listSessions),
		guardian("DELETE /v1/sessions/{id}", s.revokeSession),
		guardian("DELETE /v1/sessions", s.revokeSessions),
		guardian("POST /v1/account/password", s.changePassword),
		reauthed("POST /v1/account/email", s.changeEmail),
		suspendedOK(reauthed("GET /v1/account/export", s.exportData)),
		suspendedOK(reauthed("DELETE /v1/account", s.deleteAccount)),
		guardian("POST /v1/family", s.createFamily),
		suspendedOK(guardian("GET /v1/family", s.getFamily)),
		guardian("POST /v1/family/invitations", s.invite),
		guardian("DELETE /v1/family/invitations/{id}", s.revokeInvitation),
		guardian("DELETE /v1/family/members/{account_id}", s.removeGuardian),
		guardian("POST /v1/family/leave", s.leaveFamily),
		suspendedOK(reauthed("POST /v1/family/owner", s.transferOwnership)),
		guardian("POST /v1/family/minors", s.createMinor),
		guardian("POST /v1/family/minors/{id}/consent", s.grantConsent),
		guardian("PATCH /v1/family/minors/{id}", s.updateMinor),
		reauthed("DELETE /v1/family/minors/{id}", s.deleteMinor),
		suspendedOK(reauthed("DELETE /v1/family", s.deleteFamily)),
		guardian("POST /v1/invitations/lookup", s.lookupInvitation),
		guardian("POST /v1/invitations/accept", s.acceptInvitation),
		guardian("GET /v1/invitations", s.receivedInvitations),
		guardian("POST /v1/invitations/{id}/accept", s.acceptInvitationByID),
		guardian("GET /v1/parental/pin", s.getPIN),
		reauthed("PUT /v1/parental/pin", s.setPIN),
		guardian("POST /v1/parental/pin/verify", s.verifyPIN),
		guardian("POST /v1/parental/kid-mode", s.enterKidMode),
		guardian("POST /v1/parental/link-codes", s.createLinkCode),
		guardian("GET /v1/parental/devices", s.listDevices),
		guardian("DELETE /v1/parental/devices/{id}", s.unlinkDevice),
		// Privileged MFA, for any role holder. A
		// stolen session alone cannot bind an attacker's authenticator:
		// enrolling needs a fresh re-authentication. The staff kind never
		// requires the elevation on its own, or nobody could reach the
		// challenge; only new recovery codes need it.
		staffRoute("GET /v1/staff/mfa", s.mfaStatus),
		staffReauthed("POST /v1/staff/mfa/enrollment", s.startMFAEnrollment),
		staffRoute("POST /v1/staff/mfa/enrollment/confirm", s.confirmMFAEnrollment),
		staffRoute("POST /v1/staff/mfa/challenge", s.mfaChallenge),
		{Route: Route{Pattern: "POST /v1/staff/mfa/recovery-codes", Kind: StaffRoute}, h: s.regenerateRecoveryCodes, reauth: true, elevated: true},
		guardian("POST /v1/suggestions", s.suggest),
		guardian("GET /v1/suggestions", s.listSuggestions),
		guardian("GET /v1/family/minors/{id}/catalog", s.minorCatalog),
		guardian("PUT /v1/family/minors/{id}/hidden/{video}", s.hide),
		guardian("DELETE /v1/family/minors/{id}/hidden/{video}", s.unhide),
		guardian("POST /v1/reports", s.report),
		guardian("GET /v1/family/thumbs/{video}", s.familyThumb),
		guardian("GET /v1/screentime/minors/{id}", s.getScreenTime),
		guardian("PUT /v1/screentime/minors/{id}", s.putScreenTime),
		guardian("POST /v1/screentime/minors/{id}/extend", s.guardianExtend),
		guardian("GET /v1/screentime/minors/{id}/usage", s.screenTimeUsage),
		public("POST /v1/devices/redeem", s.redeem),
		kidConsented("GET /v1/child/profile", s.childProfile),
		kid("POST /v1/child/unlock", s.unlock),
		kid("POST /v1/child/profiles", s.childProfiles),
		kid("PUT /v1/child/profile", s.switchProfile),
		kidConsented("GET /v1/child/catalog", s.childCatalog),
		kidConsented("GET /v1/child/thumbs/{video}", s.childThumb),
		kidConsented("POST /v1/child/plays", s.play),
		kidConsented("POST /v1/child/plays/{id}/beat", s.beat),
		kidConsented("POST /v1/child/time/extend", s.childExtend),
		kidConsented("POST /v1/child/videos/{id}/unavailable", s.unavailable),
		// Curators answer the list; moderators and admins read it to word
		// what a curator marked, so any role holder may read it.
		staffRoute("GET /v1/curation/checklist", s.checklist),
		curator("GET /v1/curation/themes", s.themes),
		curator("GET /v1/curation/queue", s.queue),
		curator("GET /v1/curation/videos", s.approvedVideos),
		curator("GET /v1/curation/videos/{id}", s.curationVideo),
		curator("POST /v1/curation/videos/{id}/reviews", s.review),
		curator("POST /v1/curation/packs", s.composePack),
		curator("GET /v1/curation/packs", s.listPacks),
		curator("GET /v1/curation/packs/limits", s.packLimits),
		curator("GET /v1/curation/packs/{id}", s.curationPack),
		curator("PUT /v1/curation/packs/{id}", s.recomposePack),
		curator("POST /v1/curation/packs/{id}/reviews", s.reviewPack),
		// The team: every write is re-authenticated and
		// carries a reason; no route grants or revokes admin.
		admin("GET /v1/admin/staff", s.listStaff),
		adminReauthed("POST /v1/admin/staff", s.grantStaff),
		adminReauthed("PATCH /v1/admin/staff/{account_id}/curator", s.patchStaffCurator),
		adminReauthed("POST /v1/admin/staff/{account_id}/roles/{role}/revoke", s.revokeStaff),
		admin("GET /v1/admin/packs", s.adminPacks),
		admin("GET /v1/admin/packs/{id}", s.adminPack),
		// A stolen admin session cannot take pacotinhos down unnoticed:
		// removal needs a fresh re-authentication (packs, Security).
		adminReauthed("POST /v1/admin/packs/{id}/remove", s.removePack),
		// The account directory: an exact-match lookup
		// with a reason, and support actions that each need a fresh
		// re-authentication. No route lists or exports accounts.
		admin("POST /v1/admin/accounts/lookup", s.lookupAccount),
		adminReauthed("POST /v1/admin/accounts/{account_id}/sessions/revoke", s.revokeAccountSessions),
		adminReauthed("POST /v1/admin/accounts/{account_id}/devices/{device_id}/unlink", s.unlinkAccountDevice),
		adminReauthed("POST /v1/admin/accounts/{account_id}/password-reset", s.sendAccountPasswordReset),
		// Suspension: never oneself, never an admin,
		// each re-authenticated, with a reason, audited in its transaction.
		adminReauthed("POST /v1/admin/accounts/{account_id}/suspend", s.suspendAccount),
		adminReauthed("POST /v1/admin/accounts/{account_id}/reinstate", s.reinstateAccount),
		admin("GET /v1/admin/audit", s.adminAuditLog),
		admin("GET /v1/admin/metrics", s.adminMetrics),
		// Moderation. A stolen staff session cannot remove
		// a video unnoticed: removal needs a fresh re-authentication.
		moderator("GET /v1/moderation/videos", s.heldVideos),
		moderatorReauthed("POST /v1/moderation/videos/{id}/remove", s.moderate(s.Curation.ModerateRemove)),
		moderator("POST /v1/moderation/videos/{id}/reopen", s.moderate(s.Curation.ModerateReopen)),
		// Publishing or removing a doubted video is as weighty as a
		// removal: it needs a fresh re-authentication too.
		moderatorReauthed("POST /v1/moderation/videos/{id}/decide", s.decideDoubt),
	}
}

func (s *Server) wrap(r route) http.HandlerFunc {
	switch r.Kind {
	case GuardianRoute:
		if r.reauth {
			return s.reauthed(r.SuspendedOK, r.h)
		}
		return s.authed(r.SuspendedOK, r.h)
	case CuratorRoute:
		return s.withRole([]staff.Role{staff.Curator}, staff.ErrNotCurator, r.h)
	case AdminRoute, ModeratorRoute:
		// Role, then elevation (while the switch is on), then
		// re-authentication: a guardian without the role learns not_admin
		// or not_moderator, never elevation_required or reauth_required.
		h := r.h
		if r.reauth {
			h = s.requireReauth(h)
		}
		if s.StaffMFARequired {
			h = s.requireMFA(h)
		}
		if r.Kind == ModeratorRoute {
			// Moderator first: an account holding both acts as moderator.
			return s.withRole([]staff.Role{staff.Moderator, staff.Admin}, staff.ErrNotModerator, h)
		}
		return s.withRole([]staff.Role{staff.Admin}, staff.ErrNotAdmin, h)
	case StaffRoute:
		// Role, then elevation, then re-authentication.
		h := r.h
		if r.reauth {
			h = s.requireReauth(h)
		}
		if r.elevated {
			h = s.requireElevation(h)
		}
		return s.withRole([]staff.Role{staff.Admin, staff.Moderator, staff.Curator}, staff.ErrNotStaff, h)
	case SessionRoute:
		return s.sessioned(r.SuspendedOK, r.h)
	case ChildRoute:
		if r.consent {
			return s.childAuthed(s.requireConsent(r.h))
		}
		return s.childAuthed(r.h)
	default:
		if r.bare {
			return r.h
		}
		return s.limited(r.h)
	}
}
