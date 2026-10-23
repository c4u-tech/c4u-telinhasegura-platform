package repoconfig

import (
	"image/jpeg"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

type imageSet struct {
	name, dir, pattern string
	w, h, min, max     int
}

var imageSets = []imageSet{
	{"Play phone", "app/fastlane/metadata/android/pt-BR/images/phoneScreenshots", `^(\d\d)\.jpg$`, 1080, 1920, 2, 8},
	{"Play 10-inch tablet", "app/fastlane/metadata/android/pt-BR/images/tenInchScreenshots", `^(\d\d)\.jpg$`, 1600, 2560, 2, 8},
	{"App Store iPhone 6.1-inch", "app/fastlane/screenshots/ios/pt-BR", `^(\d\d)_iphone61\.jpg$`, 1179, 2556, 1, 10},
	{"App Store iPad 13-inch", "app/fastlane/screenshots/ios/pt-BR", `^(\d\d)_ipad13\.jpg$`, 2064, 2752, 1, 10},
}

func frameNumbers(t *testing.T, s imageSet) []string {
	t.Helper()
	entries, err := os.ReadDir(filepath.Join(Root(), s.dir))
	if err != nil {
		t.Fatalf("%s: %v", s.name, err)
	}
	re := regexp.MustCompile(s.pattern)
	var nums []string
	for _, e := range entries {
		if m := re.FindStringSubmatch(e.Name()); m != nil {
			nums = append(nums, m[1])
		}
	}
	sort.Strings(nums)
	return nums
}

// Each store takes only exact sizes and a bounded number of images, and a
// JPEG carries no transparency, which both stores refuse.
func TestStoreScreenshotsHaveTheStoreSizes(t *testing.T) {
	for _, s := range imageSets {
		nums := frameNumbers(t, s)
		if len(nums) < s.min || len(nums) > s.max {
			t.Errorf("%s: %d images, the store takes %d to %d", s.name, len(nums), s.min, s.max)
		}
		re := regexp.MustCompile(s.pattern)
		entries, _ := os.ReadDir(filepath.Join(Root(), s.dir))
		for _, e := range entries {
			if !re.MatchString(e.Name()) {
				continue
			}
			f, err := os.Open(filepath.Join(Root(), s.dir, e.Name()))
			if err != nil {
				t.Fatal(err)
			}
			cfg, err := jpeg.DecodeConfig(f)
			f.Close()
			if err != nil {
				t.Errorf("%s/%s is not a JPEG: %v", s.name, e.Name(), err)
				continue
			}
			if cfg.Width != s.w || cfg.Height != s.h {
				t.Errorf("%s/%s is %dx%d, want %dx%d", s.name, e.Name(), cfg.Width, cfg.Height, s.w, s.h)
			}
		}
	}
}

// The four sets tell the same story in the same order.
func TestStoreScreenshotSetsMatch(t *testing.T) {
	want := strings.Join(frameNumbers(t, imageSets[0]), ",")
	for _, s := range imageSets[1:] {
		if got := strings.Join(frameNumbers(t, s), ","); got != want {
			t.Errorf("%s frames %s, Play phone frames %s", s.name, got, want)
		}
	}
	caps := captions(t)
	for _, n := range frameNumbers(t, imageSets[0]) {
		if caps[n] == "" {
			t.Errorf("frame %s has no caption in app/store_screens/captions.tsv", n)
		}
	}
}

func captions(t *testing.T) map[string]string {
	t.Helper()
	out := map[string]string{}
	for _, line := range strings.Split(strings.TrimRight(read(t, "app/store_screens/captions.tsv"), "\n"), "\n") {
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			t.Fatalf("captions.tsv: %q is not NN<TAB>caption", line)
		}
		out[parts[0]] = parts[1]
	}
	return out
}

// Captions are store text and appear on App Store images too.
func TestScreenshotCaptionsKeepTheCopyRules(t *testing.T) {
	for n, c := range captions(t) {
		for _, v := range copyRuleViolations(c, true) {
			t.Errorf("caption %s: %s", n, v)
		}
		if strings.Contains(strings.ToLower(c), "youtube") || freeWord.MatchString(c) {
			t.Errorf("caption %s: no YouTube or price on images", n)
		}
	}
}

func TestFeatureGraphicIsThePlaySize(t *testing.T) {
	f, err := os.Open(filepath.Join(Root(), "app/fastlane/metadata/android/pt-BR/images/featureGraphic.jpg"))
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	cfg, err := jpeg.DecodeConfig(f)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Width != 1024 || cfg.Height != 500 {
		t.Errorf("feature graphic is %dx%d, want 1024x500", cfg.Width, cfg.Height)
	}
}
