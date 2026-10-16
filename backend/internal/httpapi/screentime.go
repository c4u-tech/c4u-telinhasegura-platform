package httpapi

import (
	"net/http"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
)

// stOf is the request's child principal as screentime needs it.
func stOf(r *http.Request) screentime.Child {
	p := child(r)
	return screentime.Child{FamilyID: p.FamilyID, MinorID: p.MinorID, DeviceID: p.DeviceID}
}

// timeBody is a day state on the wire (Shapes: Time).
func timeBody(t screentime.Time) map[string]any {
	out := map[string]any{"state": string(t.State), "remaining_seconds": int(t.Remaining / time.Second)}
	if t.Reason != "" {
		out["reason"] = t.Reason
	}
	return out
}

// beat credits an open play.
func (s *Server) beat(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Playing *bool `json:"playing"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if in.Playing == nil {
		s.fail(w, screentime.ErrValidation)
		return
	}
	t, err := s.ScreenTime.Beat(r.Context(), stOf(r), r.PathValue("id"), *in.Playing)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, timeBody(t))
}

// childExtend grants time on the child's device behind the family PIN.
// Bad minutes are refused before the PIN is spent.
func (s *Server) childExtend(w http.ResponseWriter, r *http.Request) {
	var in struct {
		PIN     string `json:"pin"`
		Minutes int    `json:"minutes"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	if !screentime.ValidMinutes(in.Minutes) {
		s.fail(w, screentime.ErrValidation)
		return
	}
	p := child(r)
	if err := s.Parental.CheckChildPIN(r.Context(), p, in.PIN); err != nil {
		s.fail(w, err)
		return
	}
	account := ""
	if p.SessionID != "" {
		account = p.AccountID
	}
	t, err := s.ScreenTime.Extend(r.Context(), stOf(r), in.Minutes, account)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, timeBody(t))
}

func rulesBody(r screentime.Rules, t screentime.Today) map[string]any {
	today := timeBody(t.Time)
	today["used_seconds"] = t.UsedSeconds
	today["extension_minutes"] = t.ExtensionMinutes
	return map[string]any{
		"daily_minutes": r.DailyMinutes,
		"window_start":  screentime.FormatClock(r.WindowStart),
		"window_end":    screentime.FormatClock(r.WindowEnd),
		"time_zone":     r.TimeZone,
		"is_default":    r.IsDefault,
		"today":         today,
	}
}

func (s *Server) getScreenTime(w http.ResponseWriter, r *http.Request) {
	rules, today, err := s.ScreenTime.Rules(r.Context(), current(r).AccountID, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, rulesBody(rules, today))
}

func (s *Server) putScreenTime(w http.ResponseWriter, r *http.Request) {
	var in struct {
		DailyMinutes int    `json:"daily_minutes"`
		WindowStart  string `json:"window_start"`
		WindowEnd    string `json:"window_end"`
		TimeZone     string `json:"time_zone"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	rules, today, err := s.ScreenTime.SaveRules(r.Context(), current(r).AccountID, r.PathValue("id"),
		screentime.RulesInput{DailyMinutes: in.DailyMinutes, WindowStart: in.WindowStart, WindowEnd: in.WindowEnd, TimeZone: in.TimeZone})
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, rulesBody(rules, today))
}

func (s *Server) guardianExtend(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Minutes int `json:"minutes"`
	}
	if err := decode(w, r, &in); err != nil {
		s.fail(w, err)
		return
	}
	t, err := s.ScreenTime.GuardianExtend(r.Context(), current(r).AccountID, r.PathValue("id"), in.Minutes)
	if err != nil {
		s.fail(w, err)
		return
	}
	writeJSON(w, http.StatusOK, timeBody(t))
}

func (s *Server) screenTimeUsage(w http.ResponseWriter, r *http.Request) {
	days, err := s.ScreenTime.Usage(r.Context(), current(r).AccountID, r.PathValue("id"))
	if err != nil {
		s.fail(w, err)
		return
	}
	type dayOut struct {
		Date    string `json:"date"`
		Seconds int    `json:"seconds"`
	}
	out := make([]dayOut, len(days))
	for i, d := range days {
		out[i] = dayOut{d.Date, d.Seconds}
	}
	writeJSON(w, http.StatusOK, map[string]any{"days": out})
}
