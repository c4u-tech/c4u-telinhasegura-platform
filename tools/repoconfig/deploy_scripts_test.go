package repoconfig

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fakeRegistry: `docker pull -q <ref>` succeeds for refs in $FAKE_IMAGES;
// `docker image inspect --format <f> <ref>` answers the repo digest or the
// revision label.
const fakeRegistry = `#!/bin/sh
echo "docker $*" >> "$FAKE_LOG"
case "$1" in
  pull) for r in $FAKE_IMAGES; do [ "$r" = "$3" ] && { echo "$3"; exit 0; }; done; echo "not found" >&2; exit 1 ;;
  image)
    ref="$5"; repo="${ref%:*}"
    case "$4" in
      *RepoDigests*) echo "other.test/x@sha256:9999"; echo "$repo@sha256:1111" ;;
      *revision*) echo "${FAKE_REVISION:-rev0}" ;;
    esac ;;
esac
`

// fakeCurl answers a URL with the file $FAKE_RESPONSES/<url with every
// non-alphanumeric byte as _>, or fails like curl -f.
const fakeCurl = `#!/bin/sh
for a; do url="$a"; done
echo "curl $url" >> "$FAKE_LOG"
key="$(printf '%s' "$url" | tr -c 'A-Za-z0-9' '_')"
[ -f "$FAKE_RESPONSES/$key" ] || exit 22
cat "$FAKE_RESPONSES/$key"
`

func runScript(t *testing.T, script string, fakes map[string]string, env map[string]string, args ...string) (string, string, error) {
	t.Helper()
	bin := t.TempDir()
	tree(t, bin, fakes)
	for name := range fakes {
		if err := os.Chmod(filepath.Join(bin, name), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	log := filepath.Join(bin, "log")
	cmd := exec.Command("sh", append([]string{filepath.Join(Root(), "scripts", script)}, args...)...)
	cmd.Env = append(os.Environ(), "PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"), "FAKE_LOG="+log)
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	calls, _ := os.ReadFile(log)
	return string(out), stderr.String() + string(calls), err
}

const sha = "89abcdef0123456789abcdef0123456789abcdef"

func published(components ...string) string {
	var refs []string
	for _, c := range components {
		refs = append(refs, "ghcr.io/c4u-tech/telinhasegura-"+c+":"+sha)
	}
	return strings.Join(refs, " ")
}

func TestResolveImagesPinsEachImageByDigest(t *testing.T) {
	out, log, err := runScript(t, "resolve-images.sh", map[string]string{"docker": fakeRegistry},
		map[string]string{"FAKE_IMAGES": published("api", "web", "site", "backup"), "FAKE_REVISION": "abc123"},
		sha, "api", "web", "site", "backup")
	if err != nil {
		t.Fatalf("resolve: %v\n%s", err, log)
	}
	for _, want := range []string{
		"api=ghcr.io/c4u-tech/telinhasegura-api@sha256:1111\n",
		"api_revision=abc123\n",
		"web=ghcr.io/c4u-tech/telinhasegura-web@sha256:1111\n",
		"site=ghcr.io/c4u-tech/telinhasegura-site@sha256:1111\n",
		"backup=ghcr.io/c4u-tech/telinhasegura-backup@sha256:1111\n",
	} {
		if !strings.Contains(out, want) {
			t.Errorf("output lacks %q:\n%s", want, out)
		}
	}
}

func TestResolveImagesPrintsNothingWhenOneIsMissing(t *testing.T) {
	out, log, err := runScript(t, "resolve-images.sh", map[string]string{"docker": fakeRegistry},
		map[string]string{"FAKE_IMAGES": published("api")}, sha, "api", "web")
	if err == nil {
		t.Fatalf("resolved with web missing:\n%s", out)
	}
	if out != "" {
		t.Errorf("printed outputs on failure: %q", out)
	}
	if !strings.Contains(log, "telinhasegura-web:"+sha) {
		t.Errorf("the error does not name the missing image:\n%s", log)
	}
}

func TestResolveImagesAcceptsAnInputDigestTag(t *testing.T) {
	ref := "in-" + strings.Repeat("a", 40)
	_, log, err := runScript(t, "resolve-images.sh", map[string]string{"docker": fakeRegistry},
		map[string]string{"FAKE_IMAGES": "ghcr.io/c4u-tech/telinhasegura-site:" + ref}, ref, "site")
	if err != nil {
		t.Fatalf("resolve %s: %v\n%s", ref, err, log)
	}
}

func TestResolveImagesRefusesABadRefOrComponent(t *testing.T) {
	for _, args := range [][]string{{"HEAD", "api"}, {sha, "db"}, {sha}, {"in-zz", "api"}, {sha + "\nx", "api"}} {
		_, log, err := runScript(t, "resolve-images.sh", map[string]string{"docker": fakeRegistry}, nil, args...)
		if err == nil {
			t.Errorf("%v resolved", args)
		}
		if strings.Contains(log, "docker pull") {
			t.Errorf("%v reached the registry:\n%s", args, log)
		}
	}
}

func responses(t *testing.T, answers map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	files := map[string]string{}
	for url, body := range answers {
		key := strings.Map(func(r rune) rune {
			if r < 128 && (r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9') {
				return r
			}
			return '_'
		}, url)
		files[key] = body
	}
	tree(t, dir, files)
	return dir
}

func healthyPrd(rev string) map[string]string {
	return map[string]string{
		"https://api.telinhasegura.coding4u.tech/livez":       `{"version":"` + rev + `"}`,
		"https://app.telinhasegura.coding4u.tech/config.json": `{"apiBaseUrl":"https://api.telinhasegura.coding4u.tech","googleClientId":""}`,
		"https://telinhasegura.coding4u.tech/":                "<!DOCTYPE html>\n<html lang=\"pt-BR\">",
	}
}

func TestDeployVerifyPassesAHealthyProduction(t *testing.T) {
	_, log, err := runScript(t, "deploy-verify.sh", map[string]string{"curl": fakeCurl},
		map[string]string{"FAKE_RESPONSES": responses(t, healthyPrd("abc")), "VERIFY_PAUSE": "0"},
		"prd", "abc", "api", "web", "site", "backup")
	if err != nil {
		t.Fatalf("verify: %v\n%s", err, log)
	}
}

func TestDeployVerifyPrefixesStaging(t *testing.T) {
	answers := map[string]string{
		"https://stg.api.telinhasegura.coding4u.tech/livez":       `{"version":"abc"}`,
		"https://stg.app.telinhasegura.coding4u.tech/config.json": `{"apiBaseUrl":"https://stg.api.telinhasegura.coding4u.tech"}`,
		"https://stg.telinhasegura.coding4u.tech/":                "<html>",
	}
	_, log, err := runScript(t, "deploy-verify.sh", map[string]string{"curl": fakeCurl},
		map[string]string{"FAKE_RESPONSES": responses(t, answers), "VERIFY_PAUSE": "0"}, "stg", "abc", "api", "web", "site")
	if err != nil {
		t.Fatalf("verify: %v\n%s", err, log)
	}
}

func TestDeployVerifyFailsOnAnOldVersionNamingTheHost(t *testing.T) {
	_, log, err := runScript(t, "deploy-verify.sh", map[string]string{"curl": fakeCurl},
		map[string]string{"FAKE_RESPONSES": responses(t, healthyPrd("old")), "VERIFY_PAUSE": "0", "VERIFY_TRIES": "2"},
		"prd", "new", "api")
	if err == nil {
		t.Fatal("an old version passed")
	}
	if !strings.Contains(log, "https://api.telinhasegura.coding4u.tech/livez") {
		t.Errorf("the failure does not name the host:\n%s", log)
	}
	if n := strings.Count(log, "curl https://api.telinhasegura.coding4u.tech/livez"); n != 2 {
		t.Errorf("%d tries, want 2", n)
	}
}

func TestDeployVerifyChecksOnlyTheDeployedComponents(t *testing.T) {
	_, log, err := runScript(t, "deploy-verify.sh", map[string]string{"curl": fakeCurl},
		map[string]string{"FAKE_RESPONSES": responses(t, healthyPrd("abc")), "VERIFY_PAUSE": "0"}, "prd", "abc", "site")
	if err != nil {
		t.Fatalf("verify: %v\n%s", err, log)
	}
	if strings.Contains(log, "livez") || strings.Contains(log, "config.json") {
		t.Errorf("checked components not deployed:\n%s", log)
	}
}

func TestDeployVerifyRefusesAnUnknownEnvironment(t *testing.T) {
	if _, _, err := runScript(t, "deploy-verify.sh", map[string]string{"curl": fakeCurl}, nil, "dev", "abc", "api"); err == nil {
		t.Error("verified an environment that does not exist")
	}
}
