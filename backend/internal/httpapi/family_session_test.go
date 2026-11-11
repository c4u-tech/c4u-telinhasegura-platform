package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
)

// familySetup is ana's family: her child, Lia (5-8, 90 minutes a day),
// locked to one mobile session (kid), a second session of hers
// (guardian), the PIN 2580 and a 50-minute work Lia may watch only with
// the family. It is 09:00 in São Paulo.
func (a *api) familySetup() (guardian, kid []string, minor, work string) {
	a.t.Helper()
	tok, minor := a.lockedSession("ana@example.com")
	guardian = bearer(a.signInMobile("ana@example.com"))
	work = a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	a.lengthen(work, 50*60)
	return guardian, bearer(tok), minor, work
}

// spentToday records minutes Lia already watched today.
func (a *api) spentToday(minor string, minutes int) {
	a.t.Helper()
	a.exec(`INSERT INTO screentime_days (minor_id, day, seconds) VALUES ($1::uuid, '2026-10-02', $2)
		ON CONFLICT (minor_id, day) DO UPDATE SET seconds = EXCLUDED.seconds`, minor, minutes*60)
}

func (a *api) startSession(guardian []string, minor string, body map[string]any) resp {
	a.t.Helper()
	return a.do(http.MethodPost, "/v1/family/minors/"+minor+"/sessions", body, guardian...)
}

type sessionResp struct {
	SessionID    string `json:"session_id"`
	StartSeconds *int   `json:"start_seconds"`
}

func TestStartFamilySessionOverHTTP(t *testing.T) {
	a := newAPI(t)
	guardian, _, minor, work := a.familySetup()
	a.spentToday(minor, 50) // 40 minutes left

	r := a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "1357"})
	if r.Code != http.StatusForbidden || r.problemCode() != "invalid_pin" {
		t.Fatalf("wrong PIN: %d %s", r.Code, r.Body)
	}
	if a.count(`SELECT count(*) FROM family_sessions`) != 0 || a.count(`SELECT failed_attempts FROM family_pins`) != 1 {
		t.Fatal("a wrong PIN stored a session, or was not counted")
	}
	r = a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580"})
	var nf struct {
		Remaining int `json:"remaining_seconds"`
	}
	_ = json.Unmarshal(r.Body.Bytes(), &nf)
	if r.Code != http.StatusForbidden || r.problemCode() != "does_not_fit" || nf.Remaining != 40*60 {
		t.Fatalf("does not fit: %d %s", r.Code, r.Body)
	}
	r = a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580", "extend_minutes": 15})
	var s sessionResp
	if err := json.Unmarshal(r.Body.Bytes(), &s); r.Code != http.StatusCreated || err != nil || s.SessionID == "" ||
		s.StartSeconds == nil || *s.StartSeconds != 0 {
		t.Fatalf("with 15 minutes more: %d %s", r.Code, r.Body)
	}
	if a.count(`SELECT count(*) FROM family_sessions WHERE minor_id = $1::uuid AND used_at IS NULL`, minor) != 1 {
		t.Fatal("the session")
	}
	if !a.audit.Has(a.accountID(a.signInMobile("ana@example.com")), audit.FamilySessionStarted) {
		t.Fatal("not audited")
	}
}

func TestStartFamilySessionRefusalsOverHTTP(t *testing.T) {
	a := newAPI(t)
	guardian, _, minor, work := a.familySetup()
	solo := a.published("aaaaaaaaaaa", "bichos", "ate-4")
	tooLong := a.published("bbbbbbbbbbb", "bichos", "ate-4")
	a.lengthen(tooLong, 121*60)
	for name, id := range map[string]string{"solo": solo, "past the family ceiling": tooLong, "malformed": "abc"} {
		if r := a.startSession(guardian, minor, map[string]any{"video_id": id, "pin": "2580"}); r.problemCode() != "video_not_allowed" {
			t.Errorf("%s: %d %s", name, r.Code, r.Body)
		}
	}
	if r := a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580", "extend_minutes": 45}); r.problemCode() != "validation" {
		t.Errorf("45 minutes: %d %s", r.Code, r.Body)
	}
	a.spentToday(minor, 90)
	if r := a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580"}); r.Code != http.StatusForbidden ||
		r.problemCode() != "time_up" || r.problemReason() != "daily" {
		t.Errorf("time up: %d %s", r.Code, r.Body)
	}
	a.exec(`UPDATE minor_consents SET withdrawn_at = $2 WHERE minor_id = $1::uuid`, minor, a.now)
	if r := a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580"}); r.problemCode() != "consent_required" {
		t.Errorf("consent: %d %s", r.Code, r.Body)
	}
	if a.count(`SELECT count(*) FROM family_sessions`) != 0 {
		t.Fatal("a refused start stored a session")
	}
}

// A guardian of another family hears not_found for a child that is not
// theirs, before any PIN is compared, so neither family's PIN counter
// moves.
func TestStartFamilySessionForAnotherFamilysChild(t *testing.T) {
	a := newAPI(t)
	_, _, minor, work := a.familySetup()
	bia := a.familyOwner("bia@example.com")
	if err := a.par.SetPIN(t.Context(), a.accountID(bia), "1470"); err != nil {
		t.Fatal(err)
	}
	for _, pin := range []string{"2580", "1470", "0000"} {
		if r := a.startSession(bearer(bia), minor, map[string]any{"video_id": work, "pin": pin}); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Fatalf("%s: %d %s", pin, r.Code, r.Body)
		}
	}
	if a.count(`SELECT count(*) FROM family_sessions`) != 0 || a.count(`SELECT coalesce(sum(failed_attempts), 0) FROM family_pins`) != 0 {
		t.Fatal("stored a session or counted a PIN attempt")
	}
}

func (a *api) playFamily(kid []string, videoID, continues string) resp {
	a.t.Helper()
	return a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": videoID, "continues": continues}, kid...)
}

func TestOpenAFamilyWorkOverHTTP(t *testing.T) {
	a := newAPI(t)
	guardian, kid, minor, work := a.familySetup()
	if r := a.playFamily(kid, work, ""); r.Code != http.StatusForbidden || r.problemCode() != "video_not_allowed" {
		t.Fatalf("without a session: %d %s", r.Code, r.Body)
	}
	if r := a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580"}); r.Code != http.StatusCreated {
		t.Fatalf("start: %d %s", r.Code, r.Body)
	}
	r := a.playFamily(kid, work, "")
	var p map[string]any
	_ = json.Unmarshal(r.Body.Bytes(), &p)
	if r.Code != http.StatusCreated || p["start_seconds"] != float64(0) || p["youtube_id"] != "dQw4w9WgXcQ" {
		t.Fatalf("open: %d %v", r.Code, p)
	}
	id := p["play_id"].(string)
	if r := a.playFamily(kid, work, ""); r.problemCode() != "video_not_allowed" {
		t.Fatalf("second open: %d %s", r.Code, r.Body)
	}
	// Beats carry the position: the next session starts there.
	for _, pos := range []int{600, 1200} {
		if r := a.do(http.MethodPost, "/v1/child/plays/"+id+"/beat", map[string]any{"playing": true, "position_seconds": pos}, kid...); r.Code != http.StatusOK {
			t.Fatalf("beat: %d %s", r.Code, r.Body)
		}
		a.now = a.now.Add(30 * time.Second)
	}
	if r := a.do(http.MethodPost, "/v1/child/plays/"+id+"/beat", map[string]any{"playing": true, "position_seconds": -1}, kid...); r.Code != http.StatusOK {
		t.Fatalf("negative position: %d %s", r.Code, r.Body)
	}
	// A reopen of the play within half an hour needs no session.
	a.now = a.now.Add(time.Minute)
	if r := a.playFamily(kid, work, id); r.Code != http.StatusCreated {
		t.Fatalf("reopen: %d %s", r.Code, r.Body)
	}
	r = a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580"})
	var s sessionResp
	if err := json.Unmarshal(r.Body.Bytes(), &s); err != nil || s.StartSeconds == nil || *s.StartSeconds != 1200 {
		t.Fatalf("next session: %d %s", r.Code, r.Body)
	}
	// Ten minutes later the session is gone.
	a.now = a.now.Add(10 * time.Minute)
	if r := a.playFamily(kid, work, ""); r.problemCode() != "video_not_allowed" {
		t.Fatalf("after ten minutes: %d %s", r.Code, r.Body)
	}
}

// A solo video's play answers no start_seconds and keeps no position.
func TestASoloPlayHasNoResumeOverHTTP(t *testing.T) {
	a := newAPI(t)
	_, kid, _, _ := a.familySetup()
	solo := a.published("aaaaaaaaaaa", "bichos", "ate-4")
	r := a.playFamily(kid, solo, "")
	var p map[string]any
	_ = json.Unmarshal(r.Body.Bytes(), &p)
	if _, ok := p["start_seconds"]; r.Code != http.StatusCreated || ok {
		t.Fatalf("solo play: %d %v", r.Code, p)
	}
	a.do(http.MethodPost, "/v1/child/plays/"+p["play_id"].(string)+"/beat", map[string]any{"playing": true, "position_seconds": 100}, kid...)
	if a.count(`SELECT count(*) FROM play_positions`) != 0 {
		t.Fatal("a solo video's position was stored")
	}
}

// The child's band changes between the start and the open: the open
// re-checks the work, and one past the new band's family ceiling is
// refused.
func TestOpenRechecksTheWorkAfterABandChange(t *testing.T) {
	a := newAPI(t)
	guardian, kid, minor, work := a.familySetup()
	a.lengthen(work, 90*60)
	if r := a.startSession(guardian, minor, map[string]any{"video_id": work, "pin": "2580"}); r.Code != http.StatusCreated {
		t.Fatalf("start: %d %s", r.Code, r.Body)
	}
	a.exec(`UPDATE minors SET age_band = 'ate-4' WHERE id = $1::uuid`, minor)
	if r := a.playFamily(kid, work, ""); r.Code != http.StatusForbidden || r.problemCode() != "video_not_allowed" {
		t.Fatalf("open: %d %s", r.Code, r.Body)
	}
	if a.count(`SELECT count(*) FROM family_sessions WHERE used_at IS NULL`) != 1 {
		t.Fatal("a refused open used the session")
	}
}

// A child may report a family work that fails to play.
func TestReportAFamilyWorkUnavailableOverHTTP(t *testing.T) {
	a := newAPI(t)
	_, kid, _, work := a.familySetup()
	if r := a.do(http.MethodPost, "/v1/child/videos/"+work+"/unavailable", nil, kid...); r.Code != http.StatusAccepted {
		t.Fatalf("report: %d %s", r.Code, r.Body)
	}
}
