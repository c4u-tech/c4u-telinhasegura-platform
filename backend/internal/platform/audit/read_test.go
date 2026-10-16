package audit_test

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"maps"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
)

const (
	actor = "7d0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c11"
	bia   = "0b0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c22"
	caio  = "0c0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c33"
)

func meta(t *testing.T, raw json.RawMessage) map[string]string {
	t.Helper()
	if raw == nil {
		return nil
	}
	var m map[string]string
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("metadata %s: %v", raw, err)
	}
	return m
}

func reasons(rs []audit.Recorded) []string {
	out := make([]string, len(rs))
	for i, r := range rs {
		out[i] = r.Reason
	}
	return out
}

func TestActionsAboutNewestFirst(t *testing.T) {
	pool := dbtest.New(t)
	ctx := context.Background()
	at := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	s := audit.Store{Pool: pool, Now: func() time.Time { return at }, Log: slog.New(slog.DiscardHandler)}
	about := func(subject, reason string) {
		s.RecordAction(ctx, audit.Action{Actor: actor, ActorRole: "admin", Event: audit.AccountLookedUp,
			SubjectKind: audit.SubjectAccount, SubjectID: subject, Reason: reason, Metadata: map[string]string{"by": "email"}})
	}
	for i := range 3 {
		about(bia, fmt.Sprintf("Motivo %d.", i))
		at = at.Add(time.Second)
	}
	about(bia, "Empate A.") // two actions at one instant: the later id first
	about(bia, "Empate B.")
	about(caio, "Outra conta.")
	s.RecordAction(ctx, audit.Action{Actor: actor, ActorRole: "moderator", Event: audit.VideoRemoved,
		SubjectKind: audit.SubjectVideo, SubjectID: bia, Reason: "Um vídeo com o mesmo id."})
	s.Record(ctx, bia, audit.SignInSucceeded)
	// A row about the subject that no staff wrote (NULL actor_role) stays out.
	if _, err := pool.Exec(ctx, `INSERT INTO audit_events (account_id, event, subject_kind, subject_id, occurred_at)
		VALUES ($1::uuid, $2, 'account', $1::uuid, $3)`, bia, string(audit.SignInSucceeded), at.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}

	got, err := s.ActionsAbout(ctx, audit.SubjectAccount, bia, 4)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"Empate B.", "Empate A.", "Motivo 2.", "Motivo 1."}
	if fmt.Sprint(reasons(got)) != fmt.Sprint(want) {
		t.Fatalf("reasons %v, want %v", reasons(got), want)
	}
	g := got[0]
	if g.ID == 0 || !g.OccurredAt.Equal(at) || g.Event != audit.AccountLookedUp || g.ActorID != actor || g.ActorRole != "admin" ||
		g.SubjectKind != audit.SubjectAccount || g.SubjectID != bia || !maps.Equal(meta(t, g.Metadata), map[string]string{"by": "email"}) {
		t.Fatalf("row %+v", g)
	}
	if got, err := s.ActionsAbout(ctx, audit.SubjectAccount, "00000000-0000-0000-0000-000000000000", 20); err != nil || got == nil || len(got) != 0 {
		t.Fatalf("no action must be an empty, non-nil list: %v %v", got, err)
	}
}

func TestStaffActionsPageAndSkipGuardianEvents(t *testing.T) {
	pool := dbtest.New(t)
	ctx := context.Background()
	at := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	s := audit.Store{Pool: pool, Now: func() time.Time { return at }, Log: slog.New(slog.DiscardHandler)}
	s.RecordAction(ctx, audit.Action{Actor: actor, ActorRole: "admin", Event: audit.AccountSessionsRevoked,
		SubjectKind: audit.SubjectAccount, SubjectID: bia, Reason: "Motivo 0."}) // no metadata
	for i := 1; i <= 3; i++ {
		at = at.Add(time.Second)
		s.Record(ctx, bia, audit.SignInSucceeded)
		s.RecordAction(ctx, audit.Action{Actor: actor, ActorRole: "admin", Event: audit.AccountLookedUp,
			SubjectKind: audit.SubjectAccount, SubjectID: bia, Reason: fmt.Sprintf("Motivo %d.", i),
			Metadata: map[string]string{"by": "id"}})
	}
	at = at.Add(time.Second)
	s.RecordAction(ctx, audit.Action{Actor: actor, ActorRole: "admin", Event: audit.AccountLookedUp,
		Reason: "Motivo 4.", Metadata: map[string]string{"by": "email", "match": "none"}}) // a miss: no subject
	at = at.Add(time.Second)
	s.Record(ctx, bia, audit.KidModeEntered) // the newest row overall is a guardian's

	page, more, err := s.StaffActions(ctx, 0, 2)
	if err != nil || !more || fmt.Sprint(reasons(page)) != fmt.Sprint([]string{"Motivo 4.", "Motivo 3."}) {
		t.Fatalf("first page %v %v %v", reasons(page), more, err)
	}
	miss := page[0]
	if miss.SubjectKind != "" || miss.SubjectID != "" ||
		!maps.Equal(meta(t, miss.Metadata), map[string]string{"by": "email", "match": "none"}) {
		t.Fatalf("a miss %+v", miss)
	}
	page, more, err = s.StaffActions(ctx, 3, 2)
	if err != nil || more || fmt.Sprint(reasons(page)) != fmt.Sprint([]string{"Motivo 1.", "Motivo 0."}) {
		t.Fatalf("the exact last page %v %v %v", reasons(page), more, err)
	}
	if page[1].Metadata != nil {
		t.Fatalf("NULL metadata must read as nil: %s", page[1].Metadata)
	}
	if page, more, err := s.StaffActions(ctx, 5, 2); err != nil || more || len(page) != 0 {
		t.Fatalf("past the end %v %v %v", page, more, err)
	}
}
