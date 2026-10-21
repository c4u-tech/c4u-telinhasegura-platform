package staff

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/jackc/pgx/v5"
)

// HeldRole is one platform role of a member. DisplayRole and
// VerifiedProfessional are a curator's only.
type HeldRole struct {
	Role                 Role
	GrantedAt            time.Time
	DisplayRole          DisplayRole
	VerifiedProfessional bool
}

// Member is an account holding platform roles, as the team lists it.
type Member struct {
	AccountID string
	Email     string
	Roles     []HeldRole // by name; empty, never nil, after the last revoke
}

// GrantInput is a team appointment. DisplayRole and VerifiedProfessional
// are a curator's; a moderator's must be unset.
type GrantInput struct {
	Email                string
	Role                 Role
	DisplayRole          DisplayRole
	VerifiedProfessional *bool
	Reason               string
}

var appointed = map[Role]audit.Event{Curator: audit.CuratorAppointed, Moderator: audit.ModeratorAppointed}

// Grant gives the account with that email a curator or moderator role,
// as adminID, and records why. The reason is
// checked first, then the role, then the account, then its status under
// the account-row lock.
func (s *Service) Grant(ctx context.Context, adminID string, in GrantInput) (Member, error) {
	reason, err := CheckReason(in.Reason)
	if err != nil {
		return Member{}, err
	}
	if err := checkGrant(in); err != nil {
		return Member{}, err
	}
	verified := in.VerifiedProfessional != nil && *in.VerifiedProfessional
	id, _, err := s.insertRole(ctx, adminID, in.Email, in.Role, in.DisplayRole, verified, s.now())
	if err != nil {
		return Member{}, err
	}
	s.d.Audit.RecordAction(ctx, audit.Action{Actor: adminID, ActorRole: string(Admin), Event: appointed[in.Role],
		SubjectKind: audit.SubjectAccount, SubjectID: id, Reason: reason,
		Metadata: curatorMetadata(in.Role, in.DisplayRole, verified)})
	return s.member(ctx, id)
}

// checkGrant refuses admin (the server command's alone), an unknown
// role, and a role's wrong fields.
func checkGrant(in GrantInput) error {
	switch in.Role {
	case Admin:
		return ErrAdminCLIOnly
	case Curator:
		return checkDisplayRole(in.DisplayRole, in.VerifiedProfessional != nil && *in.VerifiedProfessional)
	case Moderator:
		if in.DisplayRole != "" || in.VerifiedProfessional != nil {
			return ErrValidation
		}
		return nil
	}
	return ErrValidation
}

// curatorMetadata is a curator's displayed role and flag, enum values
// only; nil for any other role.
func curatorMetadata(r Role, d DisplayRole, verified bool) map[string]string {
	if r != Curator {
		return nil
	}
	return map[string]string{"display_role": string(d), "verified_professional": strconv.FormatBool(verified)}
}

// member reads one account and its roles by name. An account with no
// role left is a member with none.
func (s *Service) member(ctx context.Context, accountID string) (Member, error) {
	var m Member
	err := s.d.Pool.QueryRow(ctx, `SELECT id::text, email FROM accounts WHERE id = $1::uuid`, accountID).Scan(&m.AccountID, &m.Email)
	if errors.Is(err, pgx.ErrNoRows) {
		return Member{}, ErrNotFound
	}
	if err != nil {
		return Member{}, err
	}
	rows, err := s.d.Pool.Query(ctx, `SELECT role, coalesce(display_role, ''), verified_professional, granted_at
		FROM platform_roles WHERE account_id = $1::uuid ORDER BY role`, accountID)
	if err != nil {
		return Member{}, err
	}
	m.Roles, err = pgx.CollectRows(rows, scanHeldRole)
	return m, err
}

func scanHeldRole(row pgx.CollectableRow) (HeldRole, error) { return scanHeld(row) }

// scanHeld scans a role row: the lead destinations, if any, then role,
// displayed role, verified flag and grant time.
func scanHeld(row scanner, lead ...any) (HeldRole, error) {
	var h HeldRole
	var role, display string
	err := row.Scan(append(lead, &role, &display, &h.VerifiedProfessional, &h.GrantedAt)...)
	h.Role, h.DisplayRole, h.GrantedAt = Role(role), DisplayRole(display), h.GrantedAt.UTC()
	return h, err
}

// Members lists every account holding a role, admins included, by its
// earliest grant and then its ID; each member's roles by name.
// None is an empty, non-nil list.
func (s *Service) Members(ctx context.Context) ([]Member, error) {
	rows, err := s.d.Pool.Query(ctx, `SELECT a.id::text, a.email, r.role, coalesce(r.display_role, ''), r.verified_professional, r.granted_at
		FROM platform_roles r JOIN accounts a ON a.id = r.account_id
		ORDER BY min(r.granted_at) OVER (PARTITION BY r.account_id), r.account_id, r.role`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Member{}
	for rows.Next() {
		var id, email string
		h, err := scanHeld(rows, &id, &email)
		if err != nil {
			return nil, err
		}
		if len(out) == 0 || out[len(out)-1].AccountID != id {
			out = append(out, Member{AccountID: id, Email: email})
		}
		m := &out[len(out)-1]
		m.Roles = append(m.Roles, h)
	}
	return out, rows.Err()
}

// PatchCurator changes a curator's displayed role or verified flag under
// today's rules, and records why. An admin cannot
// patch their own curator row (ErrSelfAppointment): checked after
// the reason and the malformed-id check, before any lookup.
func (s *Service) PatchCurator(ctx context.Context, adminID, accountID string, p CuratorPatch, reason string) (Member, error) {
	why, err := CheckReason(reason)
	if err != nil {
		return Member{}, err
	}
	if validID(accountID) && strings.EqualFold(adminID, accountID) {
		return Member{}, ErrSelfAppointment
	}
	c, err := s.updateCurator(ctx, accountID, p)
	if err != nil {
		return Member{}, err
	}
	s.d.Audit.RecordAction(ctx, audit.Action{Actor: adminID, ActorRole: string(Admin), Event: audit.CuratorUpdated,
		SubjectKind: audit.SubjectAccount, SubjectID: c.AccountID, Reason: why,
		Metadata: curatorMetadata(Curator, c.DisplayRole, c.VerifiedProfessional)})
	return s.member(ctx, c.AccountID)
}

var removed = map[Role]audit.Event{Curator: audit.CuratorRemoved, Moderator: audit.ModeratorRemoved}

// Revoke takes a curator or moderator role away and records why.
// A curator's reviews stay, and a review in flight
// is waited on (deleteRole). The role is refused on the account's next
// request: every route reads it anew.
func (s *Service) Revoke(ctx context.Context, adminID, accountID string, role Role, reason string) (Member, error) {
	why, err := CheckReason(reason)
	if err != nil {
		return Member{}, err
	}
	switch role {
	case Admin:
		return Member{}, ErrAdminCLIOnly
	case Curator, Moderator:
	default:
		return Member{}, ErrValidation
	}
	if err := s.deleteRole(ctx, accountID, role); err != nil {
		return Member{}, err
	}
	id := strings.ToLower(accountID) // validID passed: the canonical text of the uuid
	s.d.Audit.RecordAction(ctx, audit.Action{Actor: adminID, ActorRole: string(Admin), Event: removed[role],
		SubjectKind: audit.SubjectAccount, SubjectID: id, Reason: why})
	return s.member(ctx, id)
}
