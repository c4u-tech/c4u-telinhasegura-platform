package privacy_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
)

func TestDeleteAccountErasesTheGuardian(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	fam := f.family(ana)
	f.join(fam, bia)
	f.pin(fam)
	lia := f.minor(fam, bia, "Lia")
	f.device(fam, lia, "Tablet")
	f.linkCode(fam, lia, bia)
	f.invitation(fam, bia, "carla@example.com")
	other := f.family(f.account("dani@example.com"))
	f.exec(`INSERT INTO family_invitations (token_hash, family_id, email, invited_by, created_at, expires_at, accepted_at)
		VALUES ($1, $2::uuid, 'bia@example.com', $3::uuid, $4, $5, $4)`, f.secret("accepted-bia"), fam, ana, f.now, f.now.Add(time.Hour))
	f.exec(`INSERT INTO family_invitations (token_hash, family_id, email, invited_by, created_at, expires_at)
		VALUES ($1, $2::uuid, 'bia@example.com', $3::uuid, $4, $5)`, f.secret("pending-bia"), other, f.account("eva@example.com"), f.now, f.now.Add(time.Hour))
	s1 := f.session(bia, "Pixel 9")
	f.session(bia, "Notebook")
	f.exec(`INSERT INTO used_refresh_tokens (refresh_hash, session_id) VALUES ($1, $2::uuid)`, f.secret("used"), s1)
	f.exec(`INSERT INTO session_kid_locks (session_id, minor_id, locked_at) VALUES ($1::uuid, $2::uuid, $3)`, s1, lia, f.now)
	f.exec(`INSERT INTO email_tokens (token_hash, account_id, purpose, expires_at, created_at) VALUES ($1, $2::uuid, 'reset', $3, $3)`,
		f.secret("email-token"), bia, f.now)
	f.exec(`INSERT INTO external_identities (provider, subject, account_id, created_at) VALUES ('google', $1, $2::uuid, $3)`,
		providerSubject, bia, f.now)
	f.exec(`INSERT INTO provider_tickets (ticket_hash, kind, provider, subject, email, email_authoritative, account_id, expires_at) VALUES
		($1, 'link', 'google', 's1', 'bia@example.com', true, $4::uuid, $5),
		($2, 'signup', 'apple', 's2', 'bia@example.com', true, NULL, $5),
		($3, 'signup', 'apple', 's3', 'dani@example.com', true, NULL, $5)`,
		f.secret("t1"), f.secret("t2"), f.secret("t3"), bia, f.now.Add(time.Hour))
	f.exec(`INSERT INTO audit_events (account_id, event, occurred_at) VALUES ($1::uuid, 'signed_up', $2)`, bia, f.now)
	f.exec(`INSERT INTO access_log (account_id, ip, occurred_at) VALUES ($1::uuid, '203.0.113.7', $2)`, bia, f.now)

	if err := f.svc.DeleteAccount(ctx, bia, nil); err != nil {
		t.Fatal(err)
	}

	for _, q := range []string{
		`SELECT count(*) FROM accounts WHERE id = $1::uuid`,
		`SELECT count(*) FROM sessions WHERE account_id = $1::uuid`,
		`SELECT count(*) FROM email_tokens WHERE account_id = $1::uuid`,
		`SELECT count(*) FROM external_identities WHERE account_id = $1::uuid`,
		`SELECT count(*) FROM provider_tickets WHERE account_id = $1::uuid`,
		`SELECT count(*) FROM family_members WHERE account_id = $1::uuid`,
	} {
		if n := f.count(q, bia); n != 0 {
			t.Errorf("%s: %d rows", q, n)
		}
	}
	for q, want := range map[string]int{
		`SELECT count(*) FROM used_refresh_tokens`:                                                            0,
		`SELECT count(*) FROM session_kid_locks`:                                                              0,
		`SELECT count(*) FROM provider_tickets WHERE email = 'bia@example.com'`:                               0,
		`SELECT count(*) FROM provider_tickets WHERE email = 'dani@example.com'`:                              1,
		`SELECT count(*) FROM family_invitations WHERE email = 'bia@example.com' AND accepted_at IS NOT NULL`: 0,
		`SELECT count(*) FROM family_invitations WHERE email = 'bia@example.com' AND accepted_at IS NULL`:     1,
		`SELECT count(*) FROM families`:                                                                       2,
		`SELECT count(*) FROM family_members`:                                                                 2,
		`SELECT count(*) FROM minors`:                                                                         1,
		`SELECT count(*) FROM devices`:                                                                        1,
		`SELECT count(*) FROM family_pins`:                                                                    1,
		`SELECT count(*) FROM minor_consents WHERE withdrawn_at IS NULL`:                                      1,
	} {
		if n := f.count(q); n != want {
			t.Errorf("%s: %d rows, want %d", q, n, want)
		}
	}
	for _, q := range []string{ // the opaque survivors
		`SELECT count(*) FROM audit_events WHERE account_id = $1::uuid`,
		`SELECT count(*) FROM access_log WHERE account_id = $1::uuid`,
		`SELECT count(*) FROM minor_consents WHERE granted_by = $1::uuid`,
		`SELECT count(*) FROM family_invitations WHERE invited_by = $1::uuid`,
		`SELECT count(*) FROM link_codes WHERE created_by = $1::uuid`,
	} {
		if n := f.count(q, bia); n != 1 {
			t.Errorf("%s: %d rows, want 1", q, n)
		}
	}
	if !f.audit.Has(bia, audit.AccountDeleted) {
		t.Fatal("no account_deleted audit")
	}
	if len(f.mail.To("bia@example.com")) != 1 || len(f.mail.To("ana@example.com")) != 0 {
		t.Fatal("the confirmation goes to the deleted address only")
	}
}

func TestDeleteAccountRefusesTheOwner(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.family(ana)
	if err := f.svc.DeleteAccount(ctx, ana, nil); !errors.Is(err, privacy.ErrOwnerMustTransfer) {
		t.Fatalf("owner: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM family_members WHERE account_id = $1::uuid AND role = 'owner'`, ana); n != 1 {
		t.Fatal("a refused deletion changed the family")
	}
	if f.audit.Has(ana, audit.AccountDeleted) || len(f.mail.To("ana@example.com")) != 0 {
		t.Fatal("a refused deletion was audited or mailed")
	}
}

func TestDeleteAccountWithoutAFamily(t *testing.T) {
	f := newFixture(t)
	id := f.bareAccount("ana@example.com")
	if err := f.svc.DeleteAccount(ctx, id, nil); err != nil {
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM accounts`); n != 0 {
		t.Fatalf("%d accounts left", n)
	}
}

// failingMail fails every send.
type failingMail struct{}

func (failingMail) Send(context.Context, mail.Message) error { return errors.New("smtp down") }

func TestDeleteNoticeIsBestEffort(t *testing.T) {
	f := newFixture(t)
	id := f.account("ana@example.com")
	d := f.deps
	d.Mail = failingMail{}
	if err := privacy.NewService(d).DeleteAccount(ctx, id, nil); err != nil {
		t.Fatalf("a failed notice failed the request: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM accounts`); n != 0 {
		t.Fatal("the account survived")
	}
}

func TestDeleteAccountWaitsForTheFamilyLock(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	fam := f.family(ana)
	f.join(fam, bia)

	tx, err := f.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, `SELECT 1 FROM families WHERE id = $1::uuid FOR UPDATE`, fam); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() { done <- f.svc.DeleteAccount(ctx, bia, nil) }()
	f.waitForLockWaiter()
	// The transfer lands while the deletion waits on the family lock.
	if _, err := tx.Exec(ctx, `UPDATE family_members SET role = 'guardian' WHERE account_id = $1::uuid`, ana); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(ctx, `UPDATE family_members SET role = 'owner' WHERE account_id = $1::uuid`, bia); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; !errors.Is(err, privacy.ErrOwnerMustTransfer) {
		t.Fatalf("deletion after the transfer: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM family_members WHERE role = 'owner'`); n != 1 {
		t.Fatal("the family lost its owner")
	}
}

func TestDeleteAccountTwiceAnswersGone(t *testing.T) {
	f := newFixture(t)
	id := f.bareAccount("ana@example.com")
	if err := f.svc.DeleteAccount(ctx, id, nil); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.DeleteAccount(ctx, id, nil); !errors.Is(err, privacy.ErrAccountGone) {
		t.Fatalf("second deletion: %v", err)
	}
	if len(f.mail.To("ana@example.com")) != 1 {
		t.Fatal("the second deletion mailed again")
	}
}

func TestDeleteAccountPurgesQueuedMail(t *testing.T) {
	f := newFixture(t)
	bia := f.account("bia@example.com")
	f.exec(`INSERT INTO email_tokens (token_hash, account_id, purpose, new_email, expires_at, created_at)
		VALUES ($1, $2::uuid, 'change', 'bia.nova@example.com', $3, $3)`, f.secret("change"), bia, f.now.Add(time.Hour))
	for _, to := range []string{"bia@example.com", "bia.nova@example.com", "carla@example.com"} {
		f.exec(`INSERT INTO mail_outbox (to_address, subject, body, next_attempt_at, expires_at, created_at)
			VALUES ($1, 's', 'b', $2, $3, $2)`, to, f.now, f.now.Add(time.Hour))
	}

	if err := f.svc.DeleteAccount(ctx, bia, nil); err != nil {
		t.Fatal(err)
	}

	for to, want := range map[string]int{"bia@example.com": 0, "bia.nova@example.com": 0, "carla@example.com": 1} {
		if n := f.count(`SELECT count(*) FROM mail_outbox WHERE to_address = $1`, to); n != want {
			t.Errorf("%s: %d queued, want %d", to, n, want)
		}
	}
	if msgs := f.mail.To("bia@example.com"); len(msgs) != 1 {
		t.Fatalf("deletion notice: %d messages, want 1 after the purge", len(msgs))
	}
}
