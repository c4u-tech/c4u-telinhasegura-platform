package staff

// Support actions: an admin, re-authenticated
// by the route, ends another account's sessions, unlinks a device of its
// family or sends it a reset email, with a reason, and gets the refreshed
// sheet. Never a password, an email or a PIN set by staff.
// Each checks, in order: the reason, self, the account, the limiter
// (reset only), then writes.

import (
	"context"
	"errors"
	"strconv"
	"strings"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

// supportSubject checks the reason, refuses the caller's own account
// and reads the subject. A malformed id is answered like an
// unknown one.
func (s *Service) supportSubject(ctx context.Context, adminID, accountID, reason string) (identity.StaffAccount, string, error) {
	why, err := CheckReason(reason)
	if err != nil {
		return identity.StaffAccount{}, "", err
	}
	if !validID(accountID) {
		return identity.StaffAccount{}, "", ErrAccountNotFound
	}
	if strings.EqualFold(adminID, accountID) {
		return identity.StaffAccount{}, "", ErrSelfAction
	}
	acc, err := s.d.Accounts.AccountForStaff(ctx, accountID)
	if errors.Is(err, identity.ErrNotFound) {
		return identity.StaffAccount{}, "", ErrAccountNotFound
	}
	return acc, why, err
}

// RevokeAccountSessions ends every session of the account, a plain
// RevokeAll, and records how many were live.
func (s *Service) RevokeAccountSessions(ctx context.Context, adminID, accountID, reason string) (AccountSheet, error) {
	acc, why, err := s.supportSubject(ctx, adminID, accountID, reason)
	if err != nil {
		return AccountSheet{}, err
	}
	live, err := s.d.Sessions.List(ctx, acc.ID)
	if err != nil {
		return AccountSheet{}, err
	}
	if err := s.d.Sessions.RevokeAll(ctx, acc.ID, ""); err != nil {
		return AccountSheet{}, err
	}
	s.recordAbout(ctx, adminID, audit.AccountSessionsRevoked, acc.ID, why, map[string]string{"sessions": strconv.Itoa(len(live))})
	return s.sheet(ctx, acc)
}

// UnlinkAccountDevice deletes a device of the account's family. A
// subject without a family, or a device not in it, is ErrDeviceNotFound
// and changes nothing.
func (s *Service) UnlinkAccountDevice(ctx context.Context, adminID, accountID, deviceID, reason string) (AccountSheet, error) {
	acc, why, err := s.supportSubject(ctx, adminID, accountID, reason)
	if err != nil {
		return AccountSheet{}, err
	}
	m, ok, err := s.d.Families.Membership(ctx, acc.ID)
	if err != nil {
		return AccountSheet{}, err
	}
	if !ok {
		return AccountSheet{}, ErrDeviceNotFound
	}
	err = s.d.Devices.UnlinkInFamily(ctx, m.FamilyID, deviceID)
	if errors.Is(err, parental.ErrNotFound) {
		return AccountSheet{}, ErrDeviceNotFound
	}
	if err != nil {
		return AccountSheet{}, err
	}
	s.recordAbout(ctx, adminID, audit.AccountDeviceUnlinked, acc.ID, why, map[string]string{"device_id": strings.ToLower(deviceID)})
	return s.sheet(ctx, acc)
}

// SendAccountPasswordReset mails the account identity's reset link,
// at most 3 times an hour per subject.
func (s *Service) SendAccountPasswordReset(ctx context.Context, adminID, accountID, reason string) (AccountSheet, error) {
	acc, why, err := s.supportSubject(ctx, adminID, accountID, reason)
	if err != nil {
		return AccountSheet{}, err
	}
	if ok, wait := s.d.ResetLimiter.Allow(acc.ID); !ok {
		return AccountSheet{}, &ThrottledError{RetryAfter: wait}
	}
	if err := s.d.Accounts.SendPasswordReset(ctx, acc.ID); err != nil {
		return AccountSheet{}, err
	}
	s.recordAbout(ctx, adminID, audit.AccountPasswordResetSent, acc.ID, why, nil)
	return s.sheet(ctx, acc)
}
