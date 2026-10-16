package curation_test

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// heldVideo inserts a video held in round 1.
func (f *fixture) heldVideo(youtubeID string) string {
	f.t.Helper()
	id := f.video(youtubeID)
	f.exec(`UPDATE videos SET state = 'held', held_reason = 'review' WHERE id = $1::uuid`, id)
	return id
}

// remove and reopen moderate a video as the admin adminID, with a valid
// reason.
func (f *fixture) remove(adminID, videoID string) error {
	return f.svc.ModerateRemove(ctx, curation.Moderation{ActorID: adminID, ActorRole: staff.Admin, Reason: "Motivo válido."}, videoID)
}

func (f *fixture) reopen(adminID, videoID string) error {
	return f.svc.ModerateReopen(ctx, curation.Moderation{ActorID: adminID, ActorRole: staff.Admin, Reason: "Motivo válido."}, videoID)
}

func TestModerateRemoveAndReopen(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	admin := f.admin("ana@example.com")
	v := f.heldVideo(ytID)

	m := curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: "  Propaganda disfarçada.  "}
	if err := f.svc.ModerateRemove(ctx, m, strings.ToUpper(v)); err != nil {
		t.Fatal(err)
	}
	if got := f.detail(v).Video; got.State != curation.Removed {
		t.Fatalf("removed %+v", got)
	}
	want := audit.Action{Actor: mod, ActorRole: "moderator", Event: audit.VideoRemoved,
		SubjectKind: audit.SubjectVideo, SubjectID: v, Reason: "Propaganda disfarçada."}
	if a, ok := f.audit.LastAction(audit.VideoRemoved); !ok || !reflect.DeepEqual(a, want) {
		t.Fatalf("action %+v %v", a, ok)
	}
	if f.audited(audit.VideoRemoved) != 1 {
		t.Fatal("the removal was recorded twice")
	}

	if err := f.svc.ModerateReopen(ctx, curation.Moderation{ActorID: admin, ActorRole: staff.Admin, Reason: "Canal corrigiu."}, v); err != nil {
		t.Fatal(err)
	}
	if got := f.detail(v).Video; got.State != curation.Pending || got.Round != 2 {
		t.Fatalf("reopened %+v", got)
	}
	if a, _ := f.audit.LastAction(audit.VideoReopened); a.Actor != admin || a.ActorRole != "admin" || a.SubjectID != v || a.Reason != "Canal corrigiu." {
		t.Fatalf("reopen action %+v", a)
	}
}

func TestModerationChecksTheReasonFirst(t *testing.T) {
	f := newFixture(t)
	mod := f.account("mia@example.com")
	pending := f.video(ytID)
	held := f.heldVideo("heldvideo01")
	m := func(reason string) curation.Moderation {
		return curation.Moderation{ActorID: mod, ActorRole: staff.Moderator, Reason: reason}
	}
	for name, c := range map[string]struct {
		m    curation.Moderation
		id   string
		want error
	}{
		"no reason":                    {m(""), held, staff.ErrReasonRequired},
		"the reason before the lookup": {m("ab"), "abc", staff.ErrReasonRequired},
		"a malformed id":               {m("Motivo válido."), "abc", curation.ErrNotFound},
		"an unknown id":                {m("Motivo válido."), "00000000-0000-0000-0000-000000000000", curation.ErrNotFound},
		"a pending video":              {m("Motivo válido."), pending, curation.ErrStateConflict},
	} {
		if err := f.svc.ModerateRemove(ctx, c.m, c.id); !errors.Is(err, c.want) {
			t.Errorf("%s: %v, want %v", name, err, c.want)
		}
	}
	if err := f.svc.ModerateReopen(ctx, m(" "), held); !errors.Is(err, staff.ErrReasonRequired) {
		t.Fatalf("reopen without a reason: %v", err)
	}
	if len(f.audit.Actions) != 0 || f.detail(held).Video.State != curation.Held {
		t.Fatalf("a refused moderation changed something: %+v", f.audit.Actions)
	}
}
