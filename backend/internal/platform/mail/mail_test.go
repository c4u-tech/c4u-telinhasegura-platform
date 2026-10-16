package mail_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
)

func TestFileSenderWritesOneEMLPerMessage(t *testing.T) {
	dir := t.TempDir()
	s := mail.FileSender{Dir: filepath.Join(dir, "mail")}
	for range 2 {
		if err := s.Send(context.Background(), mail.Message{To: "ana@example.com", Subject: "Oi", Body: "Corpo"}); err != nil {
			t.Fatal(err)
		}
	}
	files, _ := filepath.Glob(filepath.Join(dir, "mail", "*.eml"))
	if len(files) != 2 {
		t.Fatalf("%d files, want 2", len(files))
	}
	raw, _ := os.ReadFile(files[0])
	for _, want := range []string{"To: ana@example.com", "Subject: Oi", "Corpo"} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("message lacks %q", want)
		}
	}
}
