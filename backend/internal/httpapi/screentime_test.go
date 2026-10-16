package httpapi_test

import (
	"encoding/json"
	"net/http"
	"testing"
	"time"
)

type timeResp struct {
	State     string `json:"state"`
	Reason    string `json:"reason"`
	Remaining int    `json:"remaining_seconds"`
}

func (a *api) openPlay(kid []string, videoID string) string {
	a.t.Helper()
	r := a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": videoID}, kid...)
	var p struct {
		PlayID    string `json:"play_id"`
		YouTubeID string `json:"youtube_id"`
		Remaining int    `json:"remaining_seconds"`
	}
	if err := json.Unmarshal(r.Body.Bytes(), &p); r.Code != http.StatusCreated || err != nil || p.PlayID == "" {
		a.t.Fatalf("play: %d %s", r.Code, r.Body)
	}
	return p.PlayID
}

func (a *api) beat(kid []string, playID string, playing bool) resp {
	return a.do(http.MethodPost, "/v1/child/plays/"+playID+"/beat", map[string]bool{"playing": playing}, kid...)
}

func TestPlayAndBeatOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com") // 09:00 in São Paulo
	kid := bearer(tok)
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")

	r := a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": v}, kid...)
	var p map[string]any
	_ = json.Unmarshal(r.Body.Bytes(), &p) // getJSON wants a 200; a play is a 201
	if r.Code != http.StatusCreated || p["youtube_id"] != "dQw4w9WgXcQ" || p["play_id"] == "" || p["remaining_seconds"] != float64(5400) {
		t.Fatalf("play %d %v", r.Code, p)
	}
	id := p["play_id"].(string)
	a.beat(kid, id, true)
	a.now = a.now.Add(30 * time.Second)
	r = a.beat(kid, id, true)
	var tm timeResp
	getJSON(t, r, &tm)
	if tm.State != "ok" || tm.Remaining != 5370 {
		t.Fatalf("beat %+v", tm)
	}
	a.now = a.now.Add(45 * time.Second)
	if r := a.beat(kid, id, true); r.Code != http.StatusConflict || r.problemCode() != "play_closed" {
		t.Fatalf("closed: %d %q", r.Code, r.problemCode())
	}
	for _, bad := range []string{"abc", "00000000-0000-0000-0000-000000000000"} {
		if r := a.beat(kid, bad, true); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Errorf("%s: %d %q", bad, r.Code, r.problemCode())
		}
	}
	if r := a.do(http.MethodPost, "/v1/child/plays/"+id+"/beat", "{}", kid...); r.problemCode() != "validation" {
		t.Fatalf("no playing field: %d %q", r.Code, r.problemCode())
	}
}

func TestTimeUpOverHTTP(t *testing.T) {
	a := newAPI(t)
	a.now = time.Date(2026, 10, 2, 23, 0, 0, 0, time.UTC) // 20:00 in São Paulo; set first, the access token lives 15 minutes
	tok, _ := a.lockedSession("ana@example.com")
	kid := bearer(tok)
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	r := a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": v}, kid...)
	if r.Code != http.StatusForbidden || r.problemCode() != "time_up" || r.problemReason() != "window" {
		t.Fatalf("play: %d %s", r.Code, r.Body)
	}
	var cat struct {
		Time timeResp `json:"time"`
	}
	getJSON(t, a.do(http.MethodGet, "/v1/child/catalog", nil, kid...), &cat)
	if cat.Time.State != "outside_window" || cat.Time.Reason != "window" {
		t.Fatalf("catalogue time %+v", cat.Time)
	}
	// An ineligible video still says so first.
	strict := a.published("aaaaaaaaaaa", "musica", "9-12")
	if r := a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": strict}, kid...); r.problemCode() != "video_not_allowed" {
		t.Fatalf("ineligible: %q", r.problemCode())
	}
}

func TestChildExtendOverHTTP(t *testing.T) {
	a := newAPI(t)
	a.now = time.Date(2026, 10, 2, 23, 0, 0, 0, time.UTC) // 20:00; set first, the access token lives 15 minutes
	tok, _ := a.lockedSession("ana@example.com")          // PIN 2580
	kid := bearer(tok)
	if r := a.do(http.MethodPost, "/v1/child/time/extend", map[string]any{"pin": "2580", "minutes": 45}, kid...); r.problemCode() != "validation" {
		t.Fatalf("45: %d %q", r.Code, r.problemCode())
	}
	if r := a.do(http.MethodPost, "/v1/child/time/extend", map[string]any{"pin": "1357", "minutes": 15}, kid...); r.Code != http.StatusForbidden || r.problemCode() != "invalid_pin" {
		t.Fatalf("wrong PIN: %d %q", r.Code, r.problemCode())
	}
	r := a.do(http.MethodPost, "/v1/child/time/extend", map[string]any{"pin": "2580", "minutes": 15}, kid...)
	var tm timeResp
	getJSON(t, r, &tm)
	if tm.State != "ok" || tm.Remaining != 900 {
		t.Fatalf("extend %+v", tm)
	}
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	a.openPlay(kid, v)
}

func TestBeatLimitOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com")
	kid := bearer(tok)
	id := a.openPlay(kid, a.published("dQw4w9WgXcQ", "bichos", "ate-4"))
	for range 20 {
		a.beat(kid, id, true)
	}
	if r := a.beat(kid, id, true); r.Code != http.StatusTooManyRequests || r.Header().Get("Retry-After") == "" {
		t.Fatalf("21st: %d %v", r.Code, r.Header())
	}
}

func TestGuardianRulesOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	other := a.familyOwner("bia@example.com")
	g := bearer(tok)
	path := "/v1/screentime/minors/" + minor

	var rules map[string]any
	getJSON(t, a.do(http.MethodGet, path, nil, g...), &rules)
	if rules["is_default"] != true || rules["window_start"] != "08:00" || rules["window_end"] != "19:30" ||
		rules["time_zone"] != "America/Sao_Paulo" {
		t.Fatalf("defaults %v", rules)
	}
	today := rules["today"].(map[string]any)
	if today["state"] != "ok" || today["used_seconds"] != float64(0) {
		t.Fatalf("today %v", today)
	}

	save := map[string]any{"daily_minutes": 45, "window_start": "07:00", "window_end": "18:00", "time_zone": "America/Manaus"}
	r := a.do(http.MethodPut, path, save, g...)
	getJSON(t, r, &rules)
	if rules["daily_minutes"] != float64(45) || rules["is_default"] != false || rules["time_zone"] != "America/Manaus" {
		t.Fatalf("saved %v", rules)
	}
	save["window_end"] = "06:00"
	if r := a.do(http.MethodPut, path, save, g...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "validation" {
		t.Fatalf("inverted: %d %q", r.Code, r.problemCode())
	}

	r = a.do(http.MethodPost, path+"/extend", map[string]int{"minutes": 30}, g...)
	var tm timeResp
	getJSON(t, r, &tm)
	if tm.State != "ok" {
		t.Fatalf("extend %+v", tm)
	}

	var usage struct {
		Days []struct {
			Date    string `json:"date"`
			Seconds int    `json:"seconds"`
		} `json:"days"`
	}
	getJSON(t, a.do(http.MethodGet, path+"/usage", nil, g...), &usage)
	if len(usage.Days) != 7 || usage.Days[6].Date != "2026-10-02" {
		t.Fatalf("usage %+v", usage)
	}

	for _, c := range []struct {
		method, path string
		body         any
	}{
		{http.MethodGet, path, nil},
		{http.MethodPut, path, map[string]any{"daily_minutes": 45, "window_start": "07:00", "window_end": "18:00", "time_zone": "America/Manaus"}},
		{http.MethodPost, path + "/extend", map[string]int{"minutes": 15}},
		{http.MethodGet, path + "/usage", nil},
		{http.MethodGet, "/v1/screentime/minors/abc", nil},
	} {
		if r := a.do(c.method, c.path, c.body, bearer(other)...); r.Code != http.StatusNotFound || r.problemCode() != "not_found" {
			t.Errorf("stranger %s %s: %d %q", c.method, c.path, r.Code, r.problemCode())
		}
	}
}

func TestGuardianExtendOverTheCap(t *testing.T) {
	a := newAPI(t)
	tok := a.familyOwner("ana@example.com")
	minor := a.addMinor(tok)
	path := "/v1/screentime/minors/" + minor
	a.do(http.MethodPut, path, map[string]any{"daily_minutes": 240, "window_start": "08:00", "window_end": "19:30",
		"time_zone": "America/Sao_Paulo"}, bearer(tok)...)
	if r := a.do(http.MethodPost, path+"/extend", map[string]int{"minutes": 15}, bearer(tok)...); r.Code != http.StatusUnprocessableEntity || r.problemCode() != "over_cap" {
		t.Fatalf("%d %q", r.Code, r.problemCode())
	}
}

func TestPlayOpenLimitOverHTTP(t *testing.T) {
	a := newAPI(t)
	tok, _ := a.lockedSession("ana@example.com")
	kid := bearer(tok)
	v := a.published("dQw4w9WgXcQ", "bichos", "ate-4")
	for range 30 {
		a.openPlay(kid, v)
	}
	if r := a.do(http.MethodPost, "/v1/child/plays", map[string]string{"video_id": v}, kid...); r.Code != http.StatusTooManyRequests || r.Header().Get("Retry-After") == "" {
		t.Fatalf("31st: %d %v", r.Code, r.Header())
	}
}
