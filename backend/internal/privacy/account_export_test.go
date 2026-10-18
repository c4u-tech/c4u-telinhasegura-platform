package privacy_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
)

func TestExportAccount(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	f.exec(`INSERT INTO external_identities (provider, subject, account_id, created_at) VALUES ('google', $1, $2::uuid, $3)`,
		providerSubject, ana, f.now)
	f.session(ana, "Pixel 9")
	old := f.session(ana, "Tablet antigo")
	f.exec(`UPDATE sessions SET created_at = $2, revoked_at = $3 WHERE id = $1::uuid`, old, f.now.Add(-time.Hour), f.now)
	f.exec(`INSERT INTO audit_events (account_id, event, occurred_at) VALUES
		($1::uuid, 'signed_up', $2), ($1::uuid, 'sign_in_succeeded', $3), (NULL, 'device_profile_changed', $3)`,
		ana, f.now.Add(-2*time.Hour), f.now.Add(-time.Hour))
	bia := f.account("bia@example.com")
	f.session(bia, "Outro")

	e, err := f.svc.Export(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	if e.Format != privacy.Format || !e.GeneratedAt.Equal(f.now) || e.GeneratedAt.Location() != time.UTC {
		t.Fatalf("header: %q %v", e.Format, e.GeneratedAt)
	}
	a := e.Account
	if a.ID != ana || a.Email != "ana@example.com" || !a.HasPassword ||
		a.EmailVerifiedAt == nil || !a.EmailVerifiedAt.Equal(f.now) ||
		a.TermsVersion == nil || *a.TermsVersion != "2026-10-17" || a.TermsAcceptedAt == nil || !a.TermsAcceptedAt.Equal(f.now) ||
		!a.AdultDeclaredAt.Equal(f.now) || !a.CreatedAt.Equal(f.now) || a.CreatedAt.Location() != time.UTC {
		t.Fatalf("account: %+v", a)
	}
	if len(a.LinkedProviders) != 1 || a.LinkedProviders[0].Provider != "google" || !a.LinkedProviders[0].LinkedAt.Equal(f.now) {
		t.Fatalf("providers: %+v", a.LinkedProviders)
	}
	if len(a.Sessions) != 2 || a.Sessions[0].DeviceLabel != "Tablet antigo" || a.Sessions[0].RevokedAt == nil ||
		a.Sessions[1].DeviceLabel != "Pixel 9" || a.Sessions[1].RevokedAt != nil || a.Sessions[1].Client != "mobile" {
		t.Fatalf("sessions: %+v", a.Sessions)
	}
	if len(a.Events) != 2 || a.Events[0].Event != "signed_up" || a.Events[1].Event != "sign_in_succeeded" {
		t.Fatalf("events: %+v", a.Events)
	}
	if e.Family != nil {
		t.Fatalf("family: %+v", e.Family)
	}
	if !f.audit.Has(ana, audit.DataExported) {
		t.Fatal("no data_exported audit")
	}
}

func TestExportShapeOfABareAccount(t *testing.T) {
	f := newFixture(t)
	id := f.bareAccount("ana@example.com")
	js := f.exportJSON(id)
	for _, want := range []string{
		`"format":"telinhasegura.export/1"`, `"generated_at":"2026-10-04T12:00:00Z"`,
		`"email_verified_at":null`, `"has_password":false`,
		`"linked_providers":[]`, `"sessions":[]`, `"events":[]`, `"family":null`,
		`"platform_roles":[]`, `"suggestions":[]`, `"reviews":[]`,
	} {
		if !strings.Contains(js, want) {
			t.Errorf("missing %s in %s", want, js)
		}
	}
}

func TestExportRateLimit(t *testing.T) {
	f := newFixture(t)
	ana := f.bareAccount("ana@example.com")
	bia := f.bareAccount("bia@example.com")
	for i := range 5 {
		if _, err := f.svc.Export(ctx, ana); err != nil {
			t.Fatalf("export %d: %v", i+1, err)
		}
	}
	var throttled *privacy.ThrottledError
	if _, err := f.svc.Export(ctx, ana); !errors.As(err, &throttled) || throttled.RetryAfter <= 0 {
		t.Fatalf("sixth export: %v", err)
	}
	if _, err := f.svc.Export(ctx, bia); err != nil {
		t.Fatalf("another account is limited apart: %v", err)
	}
	f.now = f.now.Add(time.Hour)
	if _, err := f.svc.Export(ctx, ana); err != nil {
		t.Fatalf("after the window: %v", err)
	}
}
