package brandcheck

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// read returns the text of a repository file.
func read(t *testing.T, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(Root(), filepath.FromSlash(rel)))
	if err != nil {
		t.Fatalf("read %s: %v", rel, err)
	}
	return string(b)
}

// The full figure is built from the identity's primitives.
func TestFullFigureGeometry(t *testing.T) {
	svg := read(t, "brand/svg/telinha-segura-mark-color.svg")
	for _, want := range []string{
		`viewBox="-6 -6 132 132"`,
		`#FFC42E`, `#0F2A30`, `#FBF6EC`, `#FF5A36`,
		`M40 20H72A26 26 0 0 1 98 46V64A26 26 0 0 1 72 90H40A26 26 0 0 1 14 64V46A26 26 0 0 1 40 20Z`, // body
		`cx="74" cy="52" r="10.5"`, `cx="77" cy="52" r="5"`, `cx="79" cy="50" r="1.7"`,
		`14 44.5 98 44.5 98 59.28 14 54.75`, // mask
	} {
		if !strings.Contains(svg, want) {
			t.Errorf("mark-color.svg lacks %q", want)
		}
	}
}

// The small tiers drop detail instead of shrinking it.
func TestSmallFiguresDropDetail(t *testing.T) {
	simple := read(t, "brand/svg/telinha-segura-mark-simplified-color.svg")
	if strings.Contains(simple, `r="1.7"`) {
		t.Error("the simplified figure keeps the eye's highlight")
	}
	mini := read(t, "brand/svg/telinha-segura-mark-mini-color.svg")
	if !strings.Contains(mini, `cx="74" cy="51" r="7.5"`) {
		t.Error("the mini figure lacks its eye")
	}
}

// One-colour figures are a single shape with the eye and brow cut out.
func TestOneColourFiguresAreOneShape(t *testing.T) {
	for file, fill := range map[string]string{
		"brand/svg/telinha-segura-mark-mono.svg":     "#0F2A30",
		"brand/svg/telinha-segura-mark-reversed.svg": "#FBF6EC",
	} {
		svg := read(t, file)
		if n := strings.Count(svg, "<path"); n != 1 {
			t.Errorf("%s has %d paths, want 1", file, n)
		}
		if !strings.Contains(svg, `fill-rule="evenodd"`) || !strings.Contains(svg, fill) {
			t.Errorf("%s is not one even-odd shape in %s", file, fill)
		}
	}
}

// The name is outlined from the bundled face, with a play for the i's dot.
func TestWordmarkOutline(t *testing.T) {
	svg := read(t, "brand/svg/telinha-segura-wordmark-color.svg")
	if !strings.Contains(svg, "M15.808 0.768") {
		t.Error("the wordmark does not start with the heavy weight's t")
	}
	if !strings.Contains(svg, "#FF5A36") {
		t.Error("the wordmark lacks its play")
	}
}

// Every signature exists in every variant, and the old small tier is gone.
func TestSignatureSet(t *testing.T) {
	m := mustManifest(t)
	for _, tier := range []string{"mark", "mark-simplified", "mark-mini", "lockup", "lockup-stacked", "lockup-endorsed", "wordmark"} {
		for _, v := range []string{"color", "color-on-dark", "mono", "reversed"} {
			p := "brand/svg/telinha-segura-" + tier + "-" + v + ".svg"
			if _, ok := m[p]; !ok {
				t.Errorf("%s is missing", p)
			}
		}
	}
	for p := range m {
		if strings.Contains(p, "monogram") {
			t.Errorf("%s remains from the previous set", p)
		}
	}
}

// Generated vectors are outlines only.
func TestVectorsCarryNoTextStyleOrMetadata(t *testing.T) {
	for p := range mustManifest(t) {
		if !strings.HasSuffix(p, ".svg") {
			continue
		}
		svg := read(t, p)
		for _, banned := range []string{"<text", "<style", "<image", "<metadata", "xmlns:"} {
			if strings.Contains(svg, banned) {
				t.Errorf("%s contains %s", p, banned)
			}
		}
	}
}
