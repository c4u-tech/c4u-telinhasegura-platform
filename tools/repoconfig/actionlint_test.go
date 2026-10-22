package repoconfig

import (
	"io"
	"path/filepath"
	"testing"

	"github.com/rhysd/actionlint"
)

// Every workflow, present and future, passes actionlint: expression
// types, job references and runner labels. Shell scripts are not checked,
// so the result is the same on every machine.
func TestWorkflowsPassActionlint(t *testing.T) {
	files, err := filepath.Glob(filepath.Join(Root(), ".github", "workflows", "*.yml"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no workflows found: %v", err)
	}
	l, err := actionlint.NewLinter(io.Discard, &actionlint.LinterOptions{})
	if err != nil {
		t.Fatal(err)
	}
	errs, err := l.LintFiles(files, nil)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range errs {
		t.Errorf("%s:%d:%d: %s [%s]", e.Filepath, e.Line, e.Column, e.Message, e.Kind)
	}
}
