package repoconfig

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const (
	holder  = "Coding For You Tecnologia Ltda."
	spdx    = "AGPL-3.0-only WITH LicenseRef-telinha-app-store-exception"
	agplSHA = "0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0"
)

func read(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(Root(), rel))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// The FSF text verbatim, so GitHub detects AGPL-3.0.
func TestLicenseIsTheVerbatimAGPL(t *testing.T) {
	sum := sha256.Sum256([]byte(read(t, "LICENSE")))
	if got := hex.EncodeToString(sum[:]); got != agplSHA {
		t.Errorf("LICENSE sha256 = %s, want the FSF agpl-3.0.txt (%s)", got, agplSHA)
	}
}

func TestLicenseCompanionsNameTheHolder(t *testing.T) {
	for _, rel := range []string{"LICENSE-EXCEPTION.md", "COPYRIGHT.md", "TRADEMARKS.md"} {
		if !strings.Contains(read(t, rel), holder) {
			t.Errorf("%s does not name %s", rel, holder)
		}
	}
	if !strings.Contains(read(t, "COPYRIGHT.md"), spdx) {
		t.Errorf("COPYRIGHT.md does not state the SPDX expression %q", spdx)
	}
}
