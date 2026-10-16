package staff_test

import (
	"errors"
	"fmt"
	"maps"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

func TestAuditLogPagesStaffActionsNewestFirst(t *testing.T) {
	f := newFixture(t)
	ana := f.admin("ana@example.com")
	bia := f.account("bia@example.com")
	for i := range 50 {
		f.now = f.now.Add(time.Second)
		f.store.RecordAction(ctx, audit.Action{Actor: ana, ActorRole: "admin", Event: audit.AccountLookedUp,
			SubjectKind: audit.SubjectAccount, SubjectID: bia, Reason: fmt.Sprintf("Motivo %02d.", i),
			Metadata: map[string]string{"by": "email"}})
		f.store.Record(ctx, bia, audit.SignInSucceeded) // a guardian's own event: never listed
	}
	page, err := f.svc.AuditLog(ctx, 0)
	if err != nil || len(page.Actions) != 50 || page.NextOffset != nil {
		t.Fatalf("exactly 50 rows must be one page with no next offset: %d %v %v", len(page.Actions), page.NextOffset, err)
	}

	dani := f.account("dani@example.com") // the moderator who acted
	gil := f.account("gil@example.com")
	f.now = f.now.Add(time.Second)
	f.store.RecordAction(ctx, audit.Action{Actor: dani, ActorRole: "moderator", Event: audit.VideoRemoved,
		SubjectKind: audit.SubjectVideo, SubjectID: "0b0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c22", Reason: "Propaganda."})
	f.store.RecordAction(ctx, audit.Action{Actor: ana, ActorRole: "admin", Event: audit.AccountSessionsRevoked,
		SubjectKind: audit.SubjectAccount, SubjectID: gil, Reason: "Empate.", Metadata: map[string]string{"sessions": "1"}})
	f.exec(`DELETE FROM accounts WHERE id IN ($1::uuid, $2::uuid)`, dani, gil) // an erased actor, an erased subject

	page, err = f.svc.AuditLog(ctx, 0)
	if err != nil || len(page.Actions) != 50 || page.NextOffset == nil || *page.NextOffset != 50 {
		t.Fatalf("first page %d %v %v", len(page.Actions), page.NextOffset, err)
	}
	tie, video, lookup := page.Actions[0], page.Actions[1], page.Actions[2]
	if tie.Reason != "Empate." || tie.SubjectID != gil || tie.SubjectKind != "account" || tie.SubjectEmailMasked != "" ||
		tie.ActorEmail != "ana@example.com" {
		t.Fatalf("ties by id, newest first; an erased subject has no email: %+v", tie)
	}
	if video.Reason != "Propaganda." || video.ActorID != dani || video.ActorEmail != "" || video.ActorRole != "moderator" ||
		video.SubjectKind != "video" || video.SubjectEmailMasked != "" {
		t.Fatalf("an erased actor and a video subject: %+v", video)
	}
	if lookup.Reason != "Motivo 49." || lookup.ActorEmail != "ana@example.com" || lookup.SubjectEmailMasked != "b•••@e•••.com" ||
		!maps.Equal(meta(t, lookup.Metadata), map[string]string{"by": "email"}) {
		t.Fatalf("a lookup %+v", lookup)
	}
	next, err := f.svc.AuditLog(ctx, *page.NextOffset)
	if err != nil || len(next.Actions) != 2 || next.NextOffset != nil ||
		next.Actions[0].Reason != "Motivo 01." || next.Actions[1].Reason != "Motivo 00." {
		t.Fatalf("second page %+v %v", next, err)
	}
	for _, e := range append(page.Actions, next.Actions...) {
		if e.ActorRole == "" {
			t.Fatalf("a guardian event reached the log: %+v", e)
		}
	}
	if _, err := f.svc.AuditLog(ctx, -1); !errors.Is(err, staff.ErrValidation) {
		t.Fatalf("a negative offset: %v", err)
	}
}
