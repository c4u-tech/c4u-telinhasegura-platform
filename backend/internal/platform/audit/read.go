package audit

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
)

// Recorded is an audit row as stored, for the staff readers.
// An empty string stands for NULL; Metadata is the
// stored JSON, nil for NULL.
type Recorded struct {
	ID          int64
	OccurredAt  time.Time
	Event       Event
	ActorID     string
	ActorRole   string
	SubjectKind SubjectKind
	SubjectID   string
	Reason      string
	Metadata    json.RawMessage
}

const recordedCols = `id, occurred_at, event, coalesce(account_id::text, ''), coalesce(actor_role, ''),
	coalesce(subject_kind, ''), coalesce(subject_id::text, ''), coalesce(reason, ''), metadata::text`

func scanRecorded(row pgx.CollectableRow) (Recorded, error) {
	var r Recorded
	var event, kind string
	var meta *string
	err := row.Scan(&r.ID, &r.OccurredAt, &event, &r.ActorID, &r.ActorRole, &kind, &r.SubjectID, &r.Reason, &meta)
	r.Event, r.SubjectKind, r.OccurredAt = Event(event), SubjectKind(kind), r.OccurredAt.UTC()
	if meta != nil {
		r.Metadata = json.RawMessage(*meta)
	}
	return r, err
}

// ActionsAbout lists the latest limit rows whose subject is (kind, id),
// newest first, ties by id descending. Only RecordAction and
// RecordActionTx write a subject, so these are staff actions; the actor_role filter keeps that true even for a
// row written another way.
func (s Store) ActionsAbout(ctx context.Context, kind SubjectKind, id string, limit int) ([]Recorded, error) {
	rows, err := s.Pool.Query(ctx, `SELECT `+recordedCols+` FROM audit_events
		WHERE subject_kind = $1 AND subject_id = $2::uuid AND actor_role IS NOT NULL ORDER BY occurred_at DESC, id DESC LIMIT $3`, string(kind), id, limit)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, scanRecorded)
}

// StaffActions pages the rows that have an actor_role, newest first, ties
// by id descending; a guardian's own events never appear.
// more reports whether a row follows the page.
func (s Store) StaffActions(ctx context.Context, offset, limit int) ([]Recorded, bool, error) {
	rows, err := s.Pool.Query(ctx, `SELECT `+recordedCols+` FROM audit_events
		WHERE actor_role IS NOT NULL ORDER BY occurred_at DESC, id DESC OFFSET $1 LIMIT $2`, offset, limit+1)
	if err != nil {
		return nil, false, err
	}
	out, err := pgx.CollectRows(rows, scanRecorded)
	if err != nil {
		return nil, false, err
	}
	if len(out) > limit {
		return out[:limit], true, nil
	}
	return out, false, nil
}
