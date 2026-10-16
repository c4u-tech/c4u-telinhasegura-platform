package staff_test

import (
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

func TestMaskEmail(t *testing.T) {
	for email, want := range map[string]string{
		"pedro@gmail.com":        "p•••@g•••.com",
		"a@uol.com.br":           "a•••@u•••.com.br",
		"x@y.org":                "x•••@y•••.org",
		"ana@mail.example.co.uk": "a•••@m•••.example.co.uk",
		"álvaro@ácme.com.br":     "á•••@á•••.com.br",
		"bob@localhost":          "b•••@l•••",
		"":                       "",
	} {
		if got := staff.MaskEmail(email); got != want {
			t.Errorf("MaskEmail(%q) = %q, want %q", email, got, want)
		}
	}
}
