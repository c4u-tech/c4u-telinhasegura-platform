package brandcheck

import (
	"io/fs"
	"path/filepath"
	"strings"
	"testing"
)

func mustManifest(t *testing.T) map[string]string {
	t.Helper()
	m, err := Manifest(Root())
	if err != nil {
		t.Fatalf("read the manifest: %v", err)
	}
	if len(m) == 0 {
		t.Fatal("the manifest lists no file")
	}
	return m
}

// A file edited by hand, or a master changed without running the
// generator, no longer has the hash the generator recorded.
func TestEveryGeneratedFileIsWhatTheGeneratorWrote(t *testing.T) {
	for path, want := range mustManifest(t) {
		got, err := Hash(Root(), path)
		if err != nil {
			t.Errorf("%s: %v", path, err)
			continue
		}
		if got != want {
			t.Errorf("%s differs from the generator's output; edit brand/source/build_brand.py and run it instead", path)
		}
	}
}

// A copy shipped from the masters is the same bytes as its master.
func TestEveryShippedCopyEqualsItsMaster(t *testing.T) {
	m := mustManifest(t)
	for copyPath, master := range map[string]string{
		"app/assets/brand/telinha-segura-wordmark-reversed.svg": "brand/svg/telinha-segura-wordmark-reversed.svg",
		"app/web/favicon.svg":                                                "brand/favicon/favicon.svg",
		"app/web/favicon.ico":                                                "brand/favicon/favicon.ico",
		"app/web/icons/apple-touch-icon.png":                                 "brand/favicon/apple-touch-icon.png",
		"app/web/icons/Icon-192.png":                                         "brand/favicon/icon-192.png",
		"app/web/icons/Icon-512.png":                                         "brand/favicon/icon-512.png",
		"app/web/icons/Icon-maskable-512.png":                                "brand/favicon/icon-maskable-512.png",
		"site/public/favicon.svg":                                            "brand/favicon/favicon.svg",
		"site/public/favicon.ico":                                            "brand/favicon/favicon.ico",
		"site/public/apple-touch-icon.png":                                   "brand/favicon/apple-touch-icon.png",
		"site/public/brand/telinha-segura-wordmark-reversed.svg":             "brand/svg/telinha-segura-wordmark-reversed.svg",
		"site/public/brand/telinha-segura-lockup-endorsed-color.svg":         "brand/svg/telinha-segura-lockup-endorsed-color.svg",
		"site/public/brand/telinha-segura-lockup-endorsed-color-on-dark.svg": "brand/svg/telinha-segura-lockup-endorsed-color-on-dark.svg",
	} {
		if _, ok := m[copyPath]; !ok {
			t.Errorf("%s is not in the manifest: the generator does not write it", copyPath)
		}
		got, err := Hash(Root(), copyPath)
		if err != nil {
			t.Errorf("%s: %v", copyPath, err)
			continue
		}
		want, err := Hash(Root(), master)
		if err != nil {
			t.Errorf("%s: %v", master, err)
			continue
		}
		if got != want {
			t.Errorf("%s differs from %s", copyPath, master)
		}
	}
}

// Every brand file in the places the generator owns comes from it: a file
// dropped there by hand would ship without a master.
func TestNoBrandFileOutsideTheManifest(t *testing.T) {
	m := mustManifest(t)
	owned := func(rel string) bool {
		switch {
		case strings.HasPrefix(rel, "brand/source/"), rel == "brand/manifest.sha256":
			return false
		case strings.HasPrefix(rel, "brand/"), strings.HasPrefix(rel, "site/public/brand/"):
			return true
		case strings.HasPrefix(rel, "app/assets/brand/"):
			return strings.HasPrefix(filepath.Base(rel), "telinha-segura-")
		}
		return false
	}
	for _, dir := range []string{"brand", "app/assets/brand", "site/public/brand"} {
		err := filepath.WalkDir(filepath.Join(Root(), dir), func(p string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() || strings.HasPrefix(d.Name(), ".") {
				return err
			}
			rel, err := filepath.Rel(Root(), p)
			if err != nil {
				return err
			}
			rel = filepath.ToSlash(rel)
			if _, ok := m[rel]; owned(rel) && !ok {
				t.Errorf("%s is not written by brand/source/build_brand.py", rel)
			}
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}
