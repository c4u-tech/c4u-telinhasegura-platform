package brandcheck

import (
	"image"
	"image/color"
	"image/png"
	"io/fs"
	"math"
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

func decode(t *testing.T, rel string) image.Image {
	t.Helper()
	f, err := os.Open(filepath.Join(Root(), filepath.FromSlash(rel)))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	img, err := png.Decode(f)
	if err != nil {
		t.Fatalf("decode %s: %v", rel, err)
	}
	return img
}

func pixel(t *testing.T, rel string, x, y int) color.RGBA {
	t.Helper()
	r, g, b, a := decode(t, rel).At(x, y).RGBA()
	return color.RGBA{uint8(r >> 8), uint8(g >> 8), uint8(b >> 8), uint8(a >> 8)}
}

// The icon carries its own ground, so no wallpaper shows through.
func TestIconGrounds(t *testing.T) {
	for file, want := range map[string]color.RGBA{
		"brand/app-icon/app-icon-1024.png":      {0x1E, 0x5B, 0x66, 0xFF},
		"brand/app-icon/app-icon-dark-1024.png": {0x0F, 0x2A, 0x30, 0xFF},
	} {
		if got := pixel(t, file, 0, 0); got != want {
			t.Errorf("%s corner is %v, want %v", file, got, want)
		}
	}
}

// On the dark ground the figure's dark parts take the brand's teal, or they would vanish.
func TestDarkIconFigureHasNoDarkParts(t *testing.T) {
	svg := read(t, "brand/app-icon/app-icon-dark.svg")
	if n := strings.Count(svg, "#0F2A30"); n != 1 {
		t.Errorf("the dark icon uses the ground colour %d times, want 1 (the ground)", n)
	}
}

// Launchers mask the foreground to a circle 66/108 of its side.
func TestAdaptiveForegroundFitsTheSafeCircle(t *testing.T) {
	img := decode(t, "brand/app-icon/android-adaptive-foreground.png")
	b := img.Bounds()
	c, r := float64(b.Dx())/2, float64(b.Dx())*33/108
	for y := b.Min.Y; y < b.Max.Y; y++ {
		for x := b.Min.X; x < b.Max.X; x++ {
			if _, _, _, a := img.At(x, y).RGBA(); a == 0 {
				continue
			}
			if math.Hypot(float64(x)+0.5-c, float64(y)+0.5-c) > r {
				t.Fatalf("pixel %d,%d lies outside the safe circle", x, y)
			}
		}
	}
}

// A browser tab can be light or dark; the favicon brings its own tile.
func TestFaviconIsTheSmallFigureOnItsTile(t *testing.T) {
	svg := read(t, "brand/favicon/favicon.svg")
	if !strings.Contains(svg, "#1E5B66") || strings.Contains(svg, "prefers-color-scheme") {
		t.Error("the favicon is not one tile for both themes")
	}
	if !strings.Contains(svg, "#FFC42E") {
		t.Error("the favicon lacks the figure")
	}
}

// The one-colour layers are drawn about the centre of what they show: the
// themed layer has no tail or legs, so centring it on the full figure's
// extents would push it off to one side.
func TestAndroidLayersAreCentred(t *testing.T) {
	for _, file := range []string{
		"brand/app-icon/android-monochrome.png",
		"brand/app-icon/android-adaptive-foreground.png",
	} {
		img := decode(t, file)
		b := img.Bounds()
		minX, minY, maxX, maxY := b.Max.X, b.Max.Y, b.Min.X, b.Min.Y
		for y := b.Min.Y; y < b.Max.Y; y++ {
			for x := b.Min.X; x < b.Max.X; x++ {
				if _, _, _, a := img.At(x, y).RGBA(); a == 0 {
					continue
				}
				minX, maxX = min(minX, x), max(maxX, x+1)
				minY, maxY = min(minY, y), max(maxY, y+1)
			}
		}
		if maxX < minX {
			t.Fatalf("%s is empty", file)
		}
		side := float64(b.Dx())
		cx, cy := float64(minX+maxX)/2, float64(minY+maxY)/2
		if math.Abs(cx-side/2) > side/100 || math.Abs(cy-side/2) > side/100 {
			t.Errorf("%s is centred at %.1f,%.1f in a %.0f px square", file, cx, cy, side)
		}
	}
}

// A page's dark theme paints the same colour as the figure's dark parts
// (tail, crown, mask, legs), so the signatures made for the brand's teal
// ground would lose them there; a page uses the one-colour signature instead.
func TestSiteNeverShowsTheTealGroundSignatures(t *testing.T) {
	root := filepath.Join(Root(), "site", "public")
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(p, ".html") {
			return err
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		if strings.Contains(string(b), "color-on-dark") {
			t.Errorf("%s references a color-on-dark brand file", p)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
