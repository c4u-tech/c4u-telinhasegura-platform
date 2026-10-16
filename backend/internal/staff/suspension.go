package staff

// Suspension: an admin, re-authenticated by the
// route, suspends another account or reinstates it, with a reason. Each
// checks the reason, self and the account (supportSubject), then acts in
// one transaction under the account-row lock, audited inside it. The notice goes after the commit, best effort, and never
// carries the reason.

import (
	"context"
	"errors"
	"slices"
	"strconv"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/jackc/pgx/v5"
)

// Suspend marks the account suspended, bumps its credential version,
// ends its sessions, drops its platform roles and records the action, in
// one transaction. Then it mails the notice. An admin is never
// suspended, which is read under the lock, and a suspended account
// is refused.
func (s *Service) Suspend(ctx context.Context, adminID, accountID, reason string) (AccountSheet, error) {
	acc, why, err := s.supportSubject(ctx, adminID, accountID, reason)
	if err != nil {
		return AccountSheet{}, err
	}
	at := s.now()
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockAccount(ctx, tx, acc.ID)
		if err != nil {
			return err
		}
		if st == identity.StatusSuspended {
			return ErrAlreadySuspended
		}
		var admin bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM platform_roles WHERE account_id = $1::uuid AND role = 'admin')`,
			acc.ID).Scan(&admin); err != nil {
			return err
		}
		if admin {
			return ErrSubjectIsAdmin
		}
		if err := identity.MarkSuspended(ctx, tx, acc.ID, at, why); err != nil {
			return err
		}
		ended, err := session.RevokeAllTx(ctx, tx, acc.ID, at)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `DELETE FROM platform_roles WHERE account_id = $1::uuid RETURNING role`, acc.ID)
		if err != nil {
			return err
		}
		dropped, err := pgx.CollectRows(rows, pgx.RowTo[string])
		if err != nil {
			return err
		}
		slices.Sort(dropped)
		return audit.RecordActionTx(ctx, tx, at, audit.Action{Actor: adminID, ActorRole: string(Admin), Event: audit.AccountSuspended,
			SubjectKind: audit.SubjectAccount, SubjectID: acc.ID, Reason: why,
			Metadata: map[string]string{"sessions": strconv.Itoa(ended), "roles": strings.Join(dropped, ",")}})
	})
	if err != nil {
		return AccountSheet{}, err
	}
	s.notify(ctx, msgSuspended(acc.Email))
	return s.sheetOf(ctx, acc.ID)
}

// Reinstate marks a suspended account active and records the action, in
// one transaction. It restores no role and revokes no session, then mails
// the notice.
func (s *Service) Reinstate(ctx context.Context, adminID, accountID, reason string) (AccountSheet, error) {
	acc, why, err := s.supportSubject(ctx, adminID, accountID, reason)
	if err != nil {
		return AccountSheet{}, err
	}
	at := s.now()
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		st, err := lockAccount(ctx, tx, acc.ID)
		if err != nil {
			return err
		}
		if st != identity.StatusSuspended {
			return ErrNotSuspended
		}
		if err := identity.MarkActive(ctx, tx, acc.ID); err != nil {
			return err
		}
		return audit.RecordActionTx(ctx, tx, at, audit.Action{Actor: adminID, ActorRole: string(Admin), Event: audit.AccountReinstated,
			SubjectKind: audit.SubjectAccount, SubjectID: acc.ID, Reason: why})
	})
	if err != nil {
		return AccountSheet{}, err
	}
	s.notify(ctx, msgReinstated(acc.Email))
	return s.sheetOf(ctx, acc.ID)
}

// lockAccount takes the account-row lock (identity.LockAccount) and
// answers the status under it. An account erased meanwhile is
// ErrAccountNotFound.
func lockAccount(ctx context.Context, tx pgx.Tx, id string) (identity.Status, error) {
	st, err := identity.LockAccount(ctx, tx, id)
	if errors.Is(err, identity.ErrNotFound) {
		return "", ErrAccountNotFound
	}
	return st, err
}

// sheetOf reads the account again and answers its sheet, so a write's
// answer shows what the write changed.
func (s *Service) sheetOf(ctx context.Context, id string) (AccountSheet, error) {
	acc, err := s.d.Accounts.AccountForStaff(ctx, id)
	if errors.Is(err, identity.ErrNotFound) {
		return AccountSheet{}, ErrAccountNotFound
	}
	if err != nil {
		return AccountSheet{}, err
	}
	return s.sheet(ctx, acc)
}

// notify mails a notice after the commit. A failed send is logged
// without the address and changes nothing.
func (s *Service) notify(ctx context.Context, m mail.Message) {
	if err := s.d.Mail.Send(context.WithoutCancel(ctx), m); err != nil {
		s.d.Log.Error("staff: suspension notice not sent", "err", err)
	}
}
