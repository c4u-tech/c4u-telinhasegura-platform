package staff_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

func TestReasonBoundaries(t *testing.T) {
	for _, c := range []struct{ raw, want string }{
		{"abc", "abc"},
		{"  " + strings.Repeat("é", 200) + "\n", strings.Repeat("é", 200)},
		{" Cuida dos retidos. ", "Cuida dos retidos."},
	} {
		if got, err := staff.CheckReason(c.raw); err != nil || got != c.want {
			t.Errorf("%q: %q %v", c.raw, got, err)
		}
	}
	for _, raw := range []string{"", "   \t\n ", " ok ", strings.Repeat("é", 201)} {
		if _, err := staff.CheckReason(raw); !errors.Is(err, staff.ErrReasonRequired) {
			t.Errorf("%q: %v", raw, err)
		}
	}
}
