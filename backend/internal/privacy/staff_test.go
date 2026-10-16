package privacy_test

import (
	"strings"
	"testing"
	"time"
)

// staffActions seeds ana (admin), bia (moderator) and caio (curator):
// ana appointed bia and caio with reasons, and bia removed a video.
func staffActions(f *fixture) (ana, bia, caio string) {
	f.t.Helper()
	ana = f.account("ana@example.com")
	bia = f.account("bia@example.com")
	caio = f.account("caio@example.com")
	f.exec(`INSERT INTO platform_roles (account_id, role, granted_at) VALUES ($1::uuid, 'admin', $3), ($2::uuid, 'moderator', $3)`,
		ana, bia, f.now)
	f.exec(`INSERT INTO audit_events (account_id, event, occurred_at, actor_role, subject_kind, subject_id, reason, metadata) VALUES
		($1::uuid, 'moderator_appointed', $4, 'admin', 'account', $2::uuid, 'Bia cuida dos retidos.', NULL),
		($1::uuid, 'curator_appointed', $4, 'admin', 'account', $3::uuid, 'Caio é pediatra.', '{"display_role": "pediatra"}'),
		($2::uuid, 'video_removed', $5, 'moderator', 'video', gen_random_uuid(), 'Propaganda disfarçada.', NULL)`,
		ana, bia, caio, f.now, f.now.Add(time.Minute))
	return ana, bia, caio
}

func TestExportListsTheActionsAboutTheAccount(t *testing.T) {
	f := newFixture(t)
	ana, bia, caio := staffActions(f)

	e, err := f.svc.Export(ctx, bia)
	if err != nil {
		t.Fatal(err)
	}
	a := e.Account
	if len(a.SubjectActions) != 1 || a.SubjectActions[0].Event != "moderator_appointed" || !a.SubjectActions[0].OccurredAt.Equal(f.now) {
		t.Fatalf("subject actions %+v", a.SubjectActions)
	}
	if len(a.PlatformRoles) != 1 || a.PlatformRoles[0].Role != "moderator" || a.PlatformRoles[0].DisplayRole != nil {
		t.Fatalf("roles %+v", a.PlatformRoles)
	}
	js := f.exportJSON(bia)
	for _, key := range []string{`"subject_actions":[{"event":"moderator_appointed","occurred_at":"2026-10-04T12:00:00Z"}]`,
		`"role":"moderator","display_role":null`, `"event":"video_removed"`} {
		if !strings.Contains(js, key) {
			t.Errorf("missing %s in %s", key, js)
		}
	}
	for _, leak := range []string{ana, caio, "Bia cuida", "Propaganda", "actor_role", "metadata", "subject_id"} {
		if strings.Contains(js, leak) {
			t.Errorf("the export carries %q", leak)
		}
	}
	if js := f.exportJSON(f.account("plain@example.com")); !strings.Contains(js, `"subject_actions":[]`) {
		t.Fatalf("no actions must be []: %s", js)
	}
}

func TestEraseClearsTheReasonsAboutTheAccount(t *testing.T) {
	f := newFixture(t)
	ana, bia, caio := staffActions(f)

	if err := f.svc.DeleteAccount(ctx, bia, nil); err != nil {
		t.Fatal(err)
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE subject_kind = 'account' AND subject_id = $1::uuid
		AND account_id = $2::uuid AND event = 'moderator_appointed' AND reason IS NULL`, bia, ana); n != 1 {
		t.Fatal("the action about the erased account must keep its ids and lose its reason")
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE account_id = $1::uuid AND event = 'video_removed'
		AND reason = 'Propaganda disfarçada.'`, bia); n != 1 {
		t.Fatal("an action the erased account took must keep its actor id and its reason")
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE subject_id = $1::uuid AND reason = 'Caio é pediatra.'`, caio); n != 1 {
		t.Fatal("the erasure cleared a reason about another account")
	}
}

func TestExportReportsTheMFAEnrollmentOnly(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	if js := f.exportJSON(ana); !strings.Contains(js, `"mfa_enrolled_at":null`) {
		t.Fatalf("no factor must export null: %s", js)
	}
	f.exec(`INSERT INTO staff_mfa (account_id, secret_sealed, confirmed_at, last_step, created_at) VALUES
		($1::uuid, '\xdeadbeef', $3, 59, $3), ($2::uuid, '\xdeadbeef', NULL, NULL, $3)`, ana, bia, f.now)
	f.exec(`INSERT INTO staff_recovery_codes (account_id, code_hash, created_at) VALUES ($1::uuid, '\xcafe', $2)`, ana, f.now)

	e, err := f.svc.Export(ctx, ana)
	if err != nil || e.Account.MFAEnrolledAt == nil || !e.Account.MFAEnrolledAt.Equal(f.now) {
		t.Fatalf("enrolled at %v (%v)", e.Account.MFAEnrolledAt, err)
	}
	js := f.exportJSON(ana)
	if !strings.Contains(js, `"mfa_enrolled_at":"`+f.now.UTC().Format(time.RFC3339)+`"`) {
		t.Fatalf("missing the enrollment time: %s", js)
	}
	for _, leak := range []string{"deadbeef", "3q2+7w", "cafe", "secret_sealed", "code_hash", "last_step"} {
		if strings.Contains(js, leak) {
			t.Errorf("the export carries %q", leak)
		}
	}
	if js := f.exportJSON(bia); !strings.Contains(js, `"mfa_enrolled_at":null`) {
		t.Fatalf("a pending factor must export null: %s", js)
	}

	if err := f.svc.DeleteAccount(ctx, ana, nil); err != nil {
		t.Fatal(err)
	}
	if f.count(`SELECT count(*) FROM staff_mfa WHERE account_id = $1::uuid`, ana) != 0 ||
		f.count(`SELECT count(*) FROM staff_recovery_codes WHERE account_id = $1::uuid`, ana) != 0 {
		t.Fatal("the factor or its codes survived the erasure")
	}
}

func TestEraseTakesTheSuspensionWithIt(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	f.exec(`UPDATE accounts SET status = 'suspended', suspended_at = $2, suspension_reason = 'Denúncia de abuso.'
		WHERE id = $1::uuid`, bia, f.now)
	f.exec(`INSERT INTO audit_events (account_id, event, occurred_at, actor_role, subject_kind, subject_id, reason, metadata)
		VALUES ($1::uuid, 'account_suspended', $3, 'admin', 'account', $2::uuid, 'Denúncia de abuso.', '{"sessions": "1", "roles": ""}')`,
		ana, bia, f.now)

	if err := f.svc.DeleteAccount(ctx, bia, nil); err != nil {
		t.Fatalf("erasing a suspended account: %v", err)
	}
	if n := f.count(`SELECT count(*) FROM accounts WHERE id = $1::uuid OR suspension_reason IS NOT NULL`, bia); n != 0 {
		t.Fatal("the suspended row, or its reason, outlived the erasure")
	}
	if n := f.count(`SELECT count(*) FROM audit_events WHERE event = 'account_suspended' AND account_id = $1::uuid
		AND subject_id = $2::uuid AND reason IS NULL`, ana, bia); n != 1 {
		t.Fatal("the suspension action must keep its ids and lose its reason")
	}
}
