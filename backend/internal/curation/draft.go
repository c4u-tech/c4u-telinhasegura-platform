package curation

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/jackc/pgx/v5"
)

// Draft is a curator's review of a video as far as they got, kept for the
// video's current round so they can pick it up where they stopped.
type Draft struct {
	ChecklistVersion string            // always the current list's: answers from a former list are filtered
	Answers          map[string]Answer // never nil
	Theme            string
	MinAgeBand       family.AgeBand
	Note             string
	BeganAt          time.Time
	PlayedToEndAt    *time.Time // when the player first reached the video's end
}

// DraftInput is what a save of a draft replaces: every field, each one
// optional, since a review under way may have answered nothing yet.
type DraftInput struct {
	ChecklistVersion string // required when Answers is not empty
	Answers          map[string]Answer
	Theme            string
	MinAgeBand       family.AgeBand
	Note             string
}

const draftCols = `checklist_version, answers, questions, coalesce(theme, ''), coalesce(min_age_band, ''), coalesce(note, ''),
	began_at, played_to_end_at`

// Draft reads curatorID's draft of the video's current round; nil when
// there is none.
func (s *Service) Draft(ctx context.Context, curatorID, videoID string) (*Draft, error) {
	if !validID(videoID) {
		return nil, ErrNotFound
	}
	var round int
	err := s.d.Pool.QueryRow(ctx, `SELECT round FROM videos WHERE id = $1::uuid`, videoID).Scan(&round)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	d, err := scanDraft(s.d.Pool.QueryRow(ctx, `SELECT `+draftCols+` FROM review_drafts
		WHERE curator_id = $1::uuid AND video_id = $2::uuid AND round = $3`, curatorID, videoID, round))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &d, nil
}

// SaveDraft replaces the content of curatorID's draft of the video's
// current round, creating it if needed. When the review began and when the
// player reached the end are kept. It is refused wherever the review
// itself would be.
func (s *Service) SaveDraft(ctx context.Context, curatorID, videoID string, in DraftInput) (Draft, error) {
	if !validID(videoID) {
		return Draft{}, ErrNotFound
	}
	in.Note = strings.TrimSpace(in.Note)
	if len(in.Answers) > 0 && in.ChecklistVersion != ChecklistVersion {
		return Draft{}, ErrChecklistOutdated
	}
	// Each answered question is stored with its text, so a later read can
	// tell an answer to a question since reworded or dropped.
	questions := make(map[string]string, len(in.Answers))
	for id, a := range in.Answers {
		item, ok := checklistItem[id]
		if !ok || a != AnswerOK && a != AnswerAppears && a != AnswerDoubt {
			return Draft{}, ErrValidation
		}
		questions[id] = item.Text
	}
	if in.Theme != "" && !validTheme(in.Theme) || in.MinAgeBand != "" && bandRank(in.MinAgeBand) == 0 ||
		utf8.RuneCountInString(in.Note) > maxReason {
		return Draft{}, ErrValidation
	}
	answers, err := json.Marshal(nonNil(in.Answers))
	if err != nil {
		return Draft{}, err
	}
	texts, err := json.Marshal(questions)
	if err != nil {
		return Draft{}, err
	}
	return s.writeDraft(ctx, curatorID, videoID, func(tx pgx.Tx, round int, now time.Time) pgx.Row {
		return tx.QueryRow(ctx, `INSERT INTO review_drafts (curator_id, video_id, round, checklist_version, answers, questions,
			theme, min_age_band, note, began_at, updated_at) VALUES ($1::uuid, $2::uuid, $3, $4, $5::text::jsonb, $6::text::jsonb,
			nullif($7::text, ''), nullif($8::text, ''), nullif($9::text, ''), $10, $10)
			ON CONFLICT (curator_id, video_id, round) DO UPDATE SET checklist_version = excluded.checklist_version,
			answers = excluded.answers, questions = excluded.questions, theme = excluded.theme,
			min_age_band = excluded.min_age_band, note = excluded.note, updated_at = excluded.updated_at
			RETURNING `+draftCols, curatorID, videoID, round, ChecklistVersion, string(answers), string(texts), in.Theme,
			string(in.MinAgeBand), in.Note, now)
	})
}

// DraftEnded records that the player reached the video's end for
// curatorID, creating the draft if needed. The first time counts.
func (s *Service) DraftEnded(ctx context.Context, curatorID, videoID string) (Draft, error) {
	if !validID(videoID) {
		return Draft{}, ErrNotFound
	}
	return s.writeDraft(ctx, curatorID, videoID, func(tx pgx.Tx, round int, now time.Time) pgx.Row {
		return tx.QueryRow(ctx, `INSERT INTO review_drafts (curator_id, video_id, round, checklist_version, began_at,
			played_to_end_at, updated_at) VALUES ($1::uuid, $2::uuid, $3, $4, $5, $5, $5)
			ON CONFLICT (curator_id, video_id, round) DO UPDATE
			SET played_to_end_at = coalesce(review_drafts.played_to_end_at, excluded.played_to_end_at),
			updated_at = excluded.updated_at
			RETURNING `+draftCols, curatorID, videoID, round, ChecklistVersion, now)
	})
}

// writeDraft runs a draft write under the video row lock and the checks a
// review makes, in the order a review makes them, so a draft write and a
// review of the same video never deadlock.
func (s *Service) writeDraft(ctx context.Context, curatorID, videoID string,
	write func(tx pgx.Tx, round int, now time.Time) pgx.Row) (Draft, error) {
	now := s.now()
	var d Draft
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		v, err := lockVideo(ctx, tx, videoID)
		if err != nil {
			return err
		}
		if _, err := reviewerMay(ctx, tx, curatorID, videoID, v, now); err != nil {
			return err
		}
		d, err = scanDraft(write(tx, v.round, now))
		return err
	})
	if err != nil {
		return Draft{}, err
	}
	return d, nil
}

// scanDraft reads a row of draftCols. An answer is kept only while its
// question is on the current list with the text it was answered under: the
// answer to a question since reworded or dropped is not carried over.
func scanDraft(row pgx.Row) (Draft, error) {
	var d Draft
	var version, band string
	var answers map[string]Answer
	var questions map[string]string
	if err := row.Scan(&version, &answers, &questions, &d.Theme, &band, &d.Note, &d.BeganAt, &d.PlayedToEndAt); err != nil {
		return Draft{}, err
	}
	d.ChecklistVersion, d.MinAgeBand, d.BeganAt = ChecklistVersion, family.AgeBand(band), d.BeganAt.UTC()
	if d.PlayedToEndAt != nil {
		at := d.PlayedToEndAt.UTC()
		d.PlayedToEndAt = &at
	}
	d.Answers = map[string]Answer{}
	for id, a := range answers {
		if item, ok := checklistItem[id]; ok && questions[id] == item.Text {
			d.Answers[id] = a
		}
	}
	return d, nil
}

func nonNil(answers map[string]Answer) map[string]Answer {
	if answers == nil {
		return map[string]Answer{}
	}
	return answers
}

// closeRound drops every draft of the video and every moderator's viewing
// of it: its round has ended, a draft of a finished round has nothing left
// to resume, and a viewing speaks only for the round it was recorded in.
func closeRound(ctx context.Context, tx pgx.Tx, videoID string) error {
	if _, err := tx.Exec(ctx, `DELETE FROM review_drafts WHERE video_id = $1::uuid`, videoID); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `DELETE FROM moderator_views WHERE video_id = $1::uuid`, videoID)
	return err
}
