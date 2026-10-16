package curation

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// ledger is a review table and its subject column. Videos and packs keep
// the same ledger shape, so they share the provenance read and the
// approval rule. Both fields are constants, never input.
type ledger struct{ table, subject string }

var (
	videoLedger = ledger{table: "video_reviews", subject: "video_id"}
	packLedger  = ledger{table: "pack_reviews", subject: "pack_id"}
)

// roundProvenance counts a round's approvals by displayed role, every
// author's (the snapshot outlives the role), with when it was published.
func roundProvenance(ctx context.Context, q querier, l ledger, subjectID string, round int, last *time.Time) (*Provenance, error) {
	rows, err := q.Query(ctx, `SELECT display_role, count(*) FROM `+l.table+`
		WHERE `+l.subject+` = $1::uuid AND round = $2 AND decision = 'approve' GROUP BY display_role`, subjectID, round)
	if err != nil {
		return nil, err
	}
	p := &Provenance{Approvals: map[DisplayRole]int{}}
	if last != nil {
		p.LastReviewedAt = last.UTC()
	}
	var role string
	var n int
	_, err = pgx.ForEachRow(rows, []any{&role, &n}, func() error {
		p.Approvals[DisplayRole(role)] = n
		return nil
	})
	return p, err
}

// approvalsReached reports whether a round holds MinApprovals approvals
// by authors who still hold the curator role. The approvals of removed or
// erased curators stay in the round and count for nothing. Videos and packs publish through it
// alone.
func (s *Service) approvalsReached(ctx context.Context, q querier, l ledger, subjectID string, round int) (bool, error) {
	var n int
	err := q.QueryRow(ctx, `SELECT count(*) FROM `+l.table+` r
		JOIN platform_roles p ON p.account_id = r.curator_id AND p.role = 'curator'
		WHERE r.`+l.subject+` = $1::uuid AND r.round = $2 AND r.decision = 'approve'`, subjectID, round).Scan(&n)
	return n >= s.d.MinApprovals, err
}
