// Package legal decides which version of a legal text a user's agreement
// may carry: the one in force, or the one before it for a while after a
// change.
package legal

import "time"

// Version is a legal text the user agrees to. When it changes, the
// previous version still counts until GraceUntil, so people on an app
// that still shows the previous text keep working until the new app is
// available to them. A zero GraceUntil means only Current counts.
type Version struct {
	Current    string
	Previous   string
	GraceUntil time.Time
}

// Accepts reports whether an agreement to version got counts at time at.
func (v Version) Accepts(got string, at time.Time) bool {
	if got == "" {
		return false
	}
	return got == v.Current || (got == v.Previous && at.Before(v.GraceUntil))
}

// Accepted lists the versions that count at time at, the current first.
func (v Version) Accepted(at time.Time) []string {
	if v.Previous != "" && at.Before(v.GraceUntil) {
		return []string{v.Current, v.Previous}
	}
	return []string{v.Current}
}
