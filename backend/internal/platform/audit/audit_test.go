package audit_test

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"maps"
	"strings"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db/dbtest"
)

func TestStoreRecordsEventsWithAndWithoutAccount(t *testing.T) {
	pool := dbtest.New(t)
	at := time.Date(2026, 10, 2, 12, 0, 0, 0, time.UTC)
	s := audit.Store{Pool: pool, Now: func() time.Time { return at }, Log: slog.New(slog.DiscardHandler)}
	ctx := context.Background()

	s.Record(ctx, "", audit.SignInFailed)
	s.Record(ctx, "7d0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c11", audit.SignedUp)

	rows, err := pool.Query(ctx, `SELECT coalesce(account_id::text, ''), event, occurred_at FROM audit_events ORDER BY id`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	var got []string
	for rows.Next() {
		var id, ev string
		var when time.Time
		if err := rows.Scan(&id, &ev, &when); err != nil {
			t.Fatal(err)
		}
		if !when.Equal(at) {
			t.Errorf("occurred_at %v", when)
		}
		got = append(got, id+"|"+ev)
	}
	want := []string{"|sign_in_failed", "7d0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c11|signed_up"}
	if len(got) != 2 || got[0] != want[0] || got[1] != want[1] {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestStoreRecordsEvenWhenTheRequestIsCancelled(t *testing.T) {
	pool := dbtest.New(t)
	s := audit.Store{Pool: pool, Now: time.Now, Log: slog.New(slog.DiscardHandler)}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	s.Record(ctx, "", audit.SignedOut)

	var n int
	if err := pool.QueryRow(context.Background(), `SELECT count(*) FROM audit_events WHERE event = $1`, string(audit.SignedOut)).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("%d rows written with a cancelled context, want 1", n)
	}
}

func TestStoreRecordsActions(t *testing.T) {
	pool := dbtest.New(t)
	at := time.Date(2026, 10, 7, 12, 0, 0, 0, time.UTC)
	s := audit.Store{Pool: pool, Now: func() time.Time { return at }, Log: slog.New(slog.DiscardHandler)}
	ctx := context.Background()
	const actor, subject = "7d0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c11", "0b0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c22"

	s.RecordAction(ctx, audit.Action{Actor: actor, ActorRole: "admin", Event: audit.CuratorAppointed,
		SubjectKind: audit.SubjectAccount, SubjectID: subject, Reason: "Pediatra da equipe.",
		Metadata: map[string]string{"display_role": "pediatra"}})
	s.RecordAction(ctx, audit.Action{Actor: actor, ActorRole: "moderator", Event: audit.VideoRemoved,
		SubjectKind: audit.SubjectVideo, SubjectID: subject, Reason: "Propaganda disfarçada."})
	s.Record(ctx, actor, audit.SignedOut)

	var who, event, role, kind, id, reason, meta string
	var when time.Time
	if err := pool.QueryRow(ctx, `SELECT account_id::text, event, occurred_at, actor_role, subject_kind, subject_id::text, reason, metadata::text
		FROM audit_events WHERE event = 'curator_appointed'`).Scan(&who, &event, &when, &role, &kind, &id, &reason, &meta); err != nil {
		t.Fatal(err)
	}
	if who != actor || role != "admin" || kind != "account" || id != subject || reason != "Pediatra da equipe." ||
		meta != `{"display_role": "pediatra"}` || !when.Equal(at) {
		t.Fatalf("action %s %s %s %s %s %q %s %v", who, event, role, kind, id, reason, meta, when)
	}
	var n int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM audit_events WHERE event = 'video_removed'
		AND actor_role = 'moderator' AND subject_kind = 'video' AND metadata IS NULL`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("an action without metadata: %d %v", n, err)
	}
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM audit_events WHERE event = 'signed_out' AND actor_role IS NULL
		AND subject_kind IS NULL AND subject_id IS NULL AND reason IS NULL AND metadata IS NULL`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("Record must leave every action column NULL: %d %v", n, err)
	}
}

func TestRecordActionLogsAWriteErrorAndNeverFails(t *testing.T) {
	pool := dbtest.New(t)
	var logs bytes.Buffer
	s := audit.Store{Pool: pool, Now: time.Now, Log: slog.New(slog.NewTextHandler(&logs, nil))}

	s.RecordAction(context.Background(), audit.Action{Event: audit.VideoRemoved, SubjectKind: audit.SubjectVideo,
		SubjectID: "not-a-uuid", Reason: "Conteúdo impróprio."})

	if !strings.Contains(logs.String(), "audit: record failed") || !strings.Contains(logs.String(), "event=video_removed") {
		t.Fatalf("the write error was not logged: %q", logs.String())
	}
	if strings.Contains(logs.String(), "Conteúdo impróprio") {
		t.Fatal("a reason reached the log")
	}
	var n int
	if err := pool.QueryRow(context.Background(), `SELECT count(*) FROM audit_events`).Scan(&n); err != nil || n != 0 {
		t.Fatalf("%d rows, %v", n, err)
	}
}

func TestRecordActionTxWritesWithItsTransaction(t *testing.T) {
	pool := dbtest.New(t)
	ctx := context.Background()
	at := time.Date(2026, 10, 8, 12, 0, 0, 0, time.UTC)
	const actor, subject = "7d0c6f1e-6a0e-4c84-9d0b-1f6f2a4b9c11", "0b6c1d2e-3f40-4a5b-8c6d-7e8f9a0b1c2d"
	a := audit.Action{Actor: actor, ActorRole: "admin", Event: audit.AccountSuspended, SubjectKind: audit.SubjectAccount,
		SubjectID: subject, Reason: "Denúncia.", Metadata: map[string]string{"sessions": "2", "roles": "curator"}}
	write := func(a audit.Action, commit bool) error {
		t.Helper()
		tx, err := pool.Begin(ctx)
		if err != nil {
			t.Fatal(err)
		}
		defer tx.Rollback(ctx)
		if err := audit.RecordActionTx(ctx, tx, at, a); err != nil {
			return err
		}
		if commit {
			return tx.Commit(ctx)
		}
		return nil
	}
	store := audit.Store{Pool: pool, Now: time.Now, Log: slog.New(slog.DiscardHandler)}

	if err := write(a, false); err != nil {
		t.Fatal(err)
	}
	if rows, err := store.ActionsAbout(ctx, audit.SubjectAccount, subject, 5); err != nil || len(rows) != 0 {
		t.Fatalf("a rolled-back action was kept: %+v %v", rows, err)
	}
	if err := write(a, true); err != nil {
		t.Fatal(err)
	}
	rows, err := store.ActionsAbout(ctx, audit.SubjectAccount, subject, 5)
	if err != nil || len(rows) != 1 {
		t.Fatalf("rows %+v %v", rows, err)
	}
	r := rows[0]
	var meta map[string]string
	if err := json.Unmarshal(r.Metadata, &meta); err != nil {
		t.Fatal(err)
	}
	if r.Event != audit.AccountSuspended || r.ActorID != actor || r.ActorRole != "admin" || r.Reason != "Denúncia." ||
		!r.OccurredAt.Equal(at) || !maps.Equal(meta, a.Metadata) {
		t.Fatalf("recorded %+v %v", r, meta)
	}
	bad := a
	bad.SubjectKind = "family" // the table's CHECK refuses it
	if err := write(bad, true); err == nil {
		t.Fatal("an action the table refuses must fail its transaction, not be logged away")
	}
}
