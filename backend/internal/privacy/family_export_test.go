package privacy_test

import (
	"encoding/base64"
	"strings"
	"testing"
	"time"
)

func TestExportFamilyAsOwner(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	fam := f.family(ana)
	f.join(fam, bia)
	f.pin(fam)
	f.exec(`INSERT INTO minor_consents (minor_id, family_id, granted_by, policy_version, granted_at, withdrawn_at, withdrawn_by)
		VALUES (gen_random_uuid(), $1::uuid, $2::uuid, '2026-10-03', $3, $4, $2::uuid)`, fam, ana, f.now.Add(-48*time.Hour), f.now.Add(-24*time.Hour))
	lia := f.minor(fam, ana, "Lia")
	f.now = f.now.Add(time.Minute)
	f.minor(fam, bia, "Teo")
	f.device(fam, lia, "Tablet da Lia")
	f.invitation(fam, ana, "carla@example.com")
	for name, col := range map[string]string{"accepted": "accepted_at = $2", "revoked": "revoked_at = $2"} {
		f.exec(`INSERT INTO family_invitations (token_hash, family_id, email, invited_by, created_at, expires_at)
			VALUES ($1, $3::uuid, $4, $5::uuid, $2, $6)`, f.secret(name), f.now, fam, name+"@example.com", ana, f.now.Add(time.Hour))
		f.exec(`UPDATE family_invitations SET `+col+` WHERE email = $1`, name+"@example.com", f.now)
	}
	f.exec(`INSERT INTO family_invitations (token_hash, family_id, email, invited_by, created_at, expires_at)
		VALUES ($1, $2::uuid, 'expired@example.com', $3::uuid, $4, $5)`, f.secret("expired"), fam, ana, f.now.Add(-48*time.Hour), f.now.Add(-time.Hour))

	e, err := f.svc.Export(ctx, ana)
	if err != nil {
		t.Fatal(err)
	}
	x := e.Family
	if x == nil || x.ID != fam || x.Role != "owner" || !x.PINSet || x.CreatedAt.Location() != time.UTC {
		t.Fatalf("family: %+v", x)
	}
	if len(x.Guardians) != 2 || x.Guardians[0].Email != "ana@example.com" || x.Guardians[0].Role != "owner" ||
		x.Guardians[1].Email != "bia@example.com" || x.Guardians[1].Role != "guardian" {
		t.Fatalf("guardians: %+v", x.Guardians)
	}
	if len(x.Invitations) != 1 || x.Invitations[0].Email != "carla@example.com" {
		t.Fatalf("invitations: %+v", x.Invitations)
	}
	if len(x.Minors) != 2 || x.Minors[0].ID != lia || x.Minors[0].Nickname != "Lia" || x.Minors[1].Nickname != "Teo" ||
		x.Minors[0].Avatar != "fox" || x.Minors[0].AgeBand != "5-8" {
		t.Fatalf("minors: %+v", x.Minors)
	}
	if len(x.Consents) != 3 || x.Consents[0].WithdrawnAt == nil || !x.Consents[0].GrantedByMe ||
		x.Consents[1].MinorID != lia || !x.Consents[1].GrantedByMe || x.Consents[2].GrantedByMe ||
		x.Consents[1].PolicyVersion != "2026-10-03" {
		t.Fatalf("consents: %+v", x.Consents)
	}
	if len(x.Devices) != 1 || x.Devices[0].MinorID != lia || x.Devices[0].Label != "Tablet da Lia" {
		t.Fatalf("devices: %+v", x.Devices)
	}
}

func TestExportFamilyAsGuardian(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	fam := f.family(ana)
	f.join(fam, bia)
	f.minor(fam, ana, "Lia")
	f.invitation(fam, ana, "carla@example.com")

	js := f.exportJSON(bia)
	for _, want := range []string{`"role":"guardian"`, `"invitations":[]`, `"granted_by_me":false`, `"pin_set":false`, `"devices":[]`} {
		if !strings.Contains(js, want) {
			t.Errorf("missing %s in %s", want, js)
		}
	}
	for _, leak := range []string{ana, "carla@example.com"} {
		if strings.Contains(js, leak) {
			t.Errorf("a guardian's export carries %s", leak)
		}
	}
}

func TestExportKeepsToTheCallersFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	dani := f.account("dani@example.com")
	f.family(ana)
	other := f.family(dani)
	kid := f.minor(other, dani, "Outra")
	f.device(other, kid, "Tablet alheio")

	js := f.exportJSON(ana)
	for _, leak := range []string{"Outra", "Tablet alheio", "dani@example.com", kid, other} {
		if strings.Contains(js, leak) {
			t.Errorf("the export carries another family's %s", leak)
		}
	}
}

func TestExportCarriesNoSecrets(t *testing.T) {
	f := newFixture(t)
	ana := f.account("ana@example.com")
	bia := f.account("bia@example.com")
	fam := f.family(ana)
	f.join(fam, bia)
	f.pin(fam)
	lia := f.minor(fam, ana, "Lia")
	f.device(fam, lia, "Tablet")
	f.linkCode(fam, lia, ana)
	f.invitation(fam, ana, "carla@example.com")
	f.session(ana, "Pixel 9")
	f.exec(`INSERT INTO external_identities (provider, subject, account_id, created_at) VALUES ('google', $1, $2::uuid, $3)`,
		providerSubject, ana, f.now)
	f.exec(`INSERT INTO email_tokens (token_hash, account_id, purpose, expires_at, created_at) VALUES ($1, $2::uuid, 'reset', $3, $3)`,
		f.secret("email-token"), ana, f.now)
	f.exec(`INSERT INTO provider_tickets (ticket_hash, kind, provider, subject, email, email_authoritative, account_id, expires_at)
		VALUES ($1, 'link', 'google', $2, 'ana@example.com', true, $3::uuid, $4)`, f.secret("ticket"), providerSubject, ana, f.now)

	js := f.exportJSON(ana)
	for _, s := range []string{passwordHash, csrfToken, pinHash, providerSubject, "seeded", bia} {
		if strings.Contains(js, s) {
			t.Errorf("the export carries %q", s)
		}
	}
	for _, b := range f.secrets {
		if strings.Contains(js, base64.StdEncoding.EncodeToString(b)) {
			t.Errorf("the export carries the hash %q", b)
		}
	}
}
