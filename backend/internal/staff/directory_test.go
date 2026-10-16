package staff_test

import (
	"errors"
	"fmt"
	"maps"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

const lookupReason = "Pedido de suporte."

func byEmail(e string) staff.LookupInput { return staff.LookupInput{Email: &e, Reason: lookupReason} }
func byID(id string) staff.LookupInput {
	return staff.LookupInput{AccountID: &id, Reason: lookupReason}
}

func TestLookupAnswersTheMaskedSheet(t *testing.T) {
	f := newFixture(t)
	created := f.now
	ana := f.admin("ana@example.com")
	bia := f.curator("bia@example.com", staff.MaePai)
	f.exec(`UPDATE accounts SET password_hash = 'x' WHERE id = $1::uuid`, bia)
	f.linkGoogle(bia)
	f.enrollFactor(bia)
	fam := f.owner(bia)
	lia := f.minor(bia)
	f.minor(bia)
	active := f.device(fam, lia, f.now)
	f.device(fam, lia, f.now.Add(-181*24*time.Hour)) // idle: left out
	f.session(bia)
	if err := f.sessions.Revoke(ctx, bia, f.session(bia)); err != nil {
		t.Fatal(err)
	}
	caio := f.account("caio@example.com")
	for i := range 22 {
		f.now = f.now.Add(time.Second)
		f.store.RecordAction(ctx, audit.Action{Actor: ana, ActorRole: "admin", Event: audit.CuratorUpdated,
			SubjectKind: audit.SubjectAccount, SubjectID: bia, Reason: fmt.Sprintf("Motivo %02d.", i),
			Metadata: map[string]string{"display_role": "mae-pai"}})
	}
	f.now = f.now.Add(time.Second)
	f.store.RecordAction(ctx, audit.Action{Actor: ana, ActorRole: "admin", Event: audit.ModeratorAppointed,
		SubjectKind: audit.SubjectAccount, SubjectID: caio, Reason: "Outra conta."})

	sh, err := f.svc.Lookup(ctx, ana, byEmail(" Bia@Example.COM "))
	if err != nil {
		t.Fatal(err)
	}
	if sh.AccountID != bia || sh.EmailMasked != "b•••@e•••.com" || !sh.EmailVerified || !sh.CreatedAt.Equal(created) || !sh.MFAEnrolled {
		t.Fatalf("sheet %+v", sh)
	}
	if !slices.Equal(sh.Providers, []string{"password", "google"}) || !slices.Equal(sh.Roles, []staff.Role{staff.Curator}) {
		t.Fatalf("providers %v roles %v", sh.Providers, sh.Roles)
	}
	if sh.Family == nil || *sh.Family != (staff.SheetFamily{Role: family.Owner, Minors: 2, Devices: 1}) {
		t.Fatalf("family %+v", sh.Family)
	}
	if len(sh.Devices) != 1 || sh.Devices[0].ID != active || !sh.Devices[0].LastSeenAt.Equal(created) {
		t.Fatalf("devices %+v", sh.Devices)
	}
	if len(sh.Sessions) != 1 || sh.Sessions[0].Client != session.Mobile {
		t.Fatalf("sessions %+v", sh.Sessions)
	}
	if len(sh.Actions) != 20 || sh.Actions[0].Reason != "Motivo 21." || sh.Actions[19].Reason != "Motivo 02." {
		t.Fatalf("the latest 20 actions about the account, newest first: %d %+v", len(sh.Actions), sh.Actions)
	}
	first := sh.Actions[0]
	if first.ActorID != ana || first.ActorEmail != "ana@example.com" || first.ActorRole != "admin" || first.Event != "curator_updated" ||
		first.SubjectKind != "account" || first.SubjectID != bia || first.SubjectEmailMasked != "b•••@e•••.com" ||
		!maps.Equal(meta(t, first.Metadata), map[string]string{"display_role": "mae-pai"}) {
		t.Fatalf("action %+v", first)
	}
	want := audit.Action{Actor: ana, ActorRole: "admin", Event: audit.AccountLookedUp, SubjectKind: audit.SubjectAccount,
		SubjectID: bia, Reason: lookupReason, Metadata: map[string]string{"by": "email"}}
	if a, ok := f.audit.LastAction(audit.AccountLookedUp); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("lookup action %+v %v", a, ok)
	}

	sh, err = f.svc.Lookup(ctx, ana, byID(strings.ToUpper(bia)))
	if err != nil || sh.AccountID != bia {
		t.Fatalf("by id: %+v %v", sh, err)
	}
	if a, _ := f.audit.LastAction(audit.AccountLookedUp); a.SubjectID != bia || !maps.Equal(a.Metadata, map[string]string{"by": "id"}) {
		t.Fatalf("lookup by id action %+v", a)
	}
}

func TestSheetWithoutAFamily(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	f.account("gil@example.com")
	sh, err := f.svc.Lookup(ctx, ana, byEmail("gil@example.com"))
	if err != nil {
		t.Fatal(err)
	}
	if sh.Family != nil || sh.MFAEnrolled || sh.Devices == nil || len(sh.Devices) != 0 || sh.Sessions == nil || len(sh.Sessions) != 0 ||
		sh.Actions == nil || len(sh.Actions) != 0 || sh.Providers == nil || len(sh.Providers) != 0 || sh.Roles == nil || len(sh.Roles) != 0 {
		t.Fatalf("an account with nothing must answer empty, non-nil lists and no family: %+v", sh)
	}
}

func TestLookupMissIsAuditedWithoutTheEmail(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	for _, in := range []staff.LookupInput{byEmail("nobody@example.com"), byID("00000000-0000-0000-0000-000000000000")} {
		if _, err := f.svc.Lookup(ctx, ana, in); !errors.Is(err, staff.ErrAccountNotFound) {
			t.Fatalf("miss: %v", err)
		}
	}
	want := []audit.Action{
		{Actor: ana, ActorRole: "admin", Event: audit.AccountLookedUp, Reason: lookupReason, Metadata: map[string]string{"by": "email", "match": "none"}},
		{Actor: ana, ActorRole: "admin", Event: audit.AccountLookedUp, Reason: lookupReason, Metadata: map[string]string{"by": "id", "match": "none"}},
	}
	if !reflect.DeepEqual(f.audit.Actions, want) {
		t.Fatalf("misses %+v", f.audit.Actions)
	}
	if strings.Contains(fmt.Sprintf("%+v", f.audit.Actions), "nobody") {
		t.Fatal("the email reached the audit")
	}
}

func TestLookupRefusalsAreNeitherAuditedNorCounted(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	f.account("bia@example.com")
	email, id, bad := "bia@example.com", "00000000-0000-0000-0000-000000000000", "not-an-id"
	for name, c := range map[string]struct {
		in   staff.LookupInput
		want error
	}{
		"both":            {staff.LookupInput{Email: &email, AccountID: &id, Reason: lookupReason}, staff.ErrValidation},
		"neither":         {staff.LookupInput{Reason: lookupReason}, staff.ErrValidation},
		"malformed id":    {staff.LookupInput{AccountID: &bad, Reason: lookupReason}, staff.ErrValidation},
		"malformed email": {staff.LookupInput{Email: &bad, Reason: lookupReason}, staff.ErrValidation},
		"no reason":       {staff.LookupInput{Email: &email}, staff.ErrReasonRequired},
		"short reason":    {staff.LookupInput{Email: &email, Reason: " ab "}, staff.ErrReasonRequired},
	} {
		for range 10 { // 60 refusals: were they counted, the 30 below would not fit
			if _, err := f.svc.Lookup(ctx, ana, c.in); !errors.Is(err, c.want) {
				t.Fatalf("%s: %v, want %v", name, err, c.want)
			}
		}
	}
	if len(f.audit.Actions) != 0 {
		t.Fatalf("a refused lookup was audited: %+v", f.audit.Actions)
	}
	for i := range 30 {
		in := byEmail("bia@example.com")
		if i%2 == 1 {
			in = byEmail("nobody@example.com")
		}
		if _, err := f.svc.Lookup(ctx, ana, in); i%2 == 0 && err != nil || i%2 == 1 && !errors.Is(err, staff.ErrAccountNotFound) {
			t.Fatalf("lookup %d: %v", i+1, err)
		}
	}
	var throttled *staff.ThrottledError
	if _, err := f.svc.Lookup(ctx, ana, byEmail("bia@example.com")); !errors.As(err, &throttled) || throttled.RetryAfter <= 0 {
		t.Fatalf("the 31st lookup in an hour: %v", err)
	}
	if len(f.audit.Actions) != 30 {
		t.Fatalf("%d audited lookups, want 30: the refused 31st must read nothing", len(f.audit.Actions))
	}
	if _, err := f.svc.Lookup(ctx, f.admin("caio@example.com"), byEmail("bia@example.com")); err != nil {
		t.Fatalf("another admin has their own budget: %v", err)
	}
	f.now = f.now.Add(time.Hour)
	if _, err := f.svc.Lookup(ctx, ana, byEmail("bia@example.com")); err != nil {
		t.Fatalf("a new hour: %v", err)
	}
}
