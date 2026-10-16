package repoconfig

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fakeDocker logs every call; `buildx imagetools inspect <ref>` succeeds
// only for refs listed (space-separated) in $FAKE_IMAGES.
const fakeDocker = `#!/bin/sh
echo "docker $*" >> "$FAKE_LOG"
if [ "$1 $2 $3" = "buildx imagetools inspect" ]; then
  for r in $FAKE_IMAGES; do [ "$r" = "$4" ] && exit 0; done
  echo "ERROR: $4: not found" >&2
  exit 1
fi
exit 0
`

func runPublish(t *testing.T, env map[string]string, args ...string) (string, string, error) {
	t.Helper()
	bin := t.TempDir()
	tree(t, bin, map[string]string{"docker": fakeDocker})
	if err := os.Chmod(filepath.Join(bin, "docker"), 0o755); err != nil {
		t.Fatal(err)
	}
	log := filepath.Join(bin, "log")
	cmd := exec.Command("sh", append([]string{filepath.Join(Root(), "scripts", "publish-image.sh")}, args...)...)
	cmd.Dir = Root()
	cmd.Env = append(os.Environ(), "PATH="+bin+string(os.PathListSeparator)+os.Getenv("PATH"), "FAKE_LOG="+log)
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	calls, _ := os.ReadFile(log)
	if err != nil {
		return string(out), stderr.String() + string(calls), err
	}
	return strings.TrimSpace(string(out)), string(calls), nil
}

func siteDigest(t *testing.T) string {
	t.Helper()
	return mustDigest(t, Root(), "site")
}

const rev = "0123456789abcdef0123456789abcdef01234567"

func TestPublishReusesAnImageWithTheSameInputs(t *testing.T) {
	in := "ghcr.io/c4u-tech/telinhasegura-site:in-" + siteDigest(t)
	out, calls, err := runPublish(t, map[string]string{"FAKE_IMAGES": in}, "reuse", "site", rev)
	if err != nil || out != "reused" {
		t.Fatalf("reuse: %q, %v\n%s", out, err, calls)
	}
	want := "docker buildx imagetools create --tag ghcr.io/c4u-tech/telinhasegura-site:" + rev + " " + in
	if !strings.Contains(calls, want) {
		t.Errorf("calls lack %q:\n%s", want, calls)
	}
	if strings.Contains(calls, "docker build ") {
		t.Errorf("a reused image was rebuilt:\n%s", calls)
	}
}

func TestPublishReportsAnAbsentImage(t *testing.T) {
	out, calls, err := runPublish(t, nil, "reuse", "site", rev)
	if err != nil || out != "absent" {
		t.Fatalf("reuse: %q, %v\n%s", out, err, calls)
	}
	if strings.Contains(calls, "imagetools create") {
		t.Errorf("tagged an image that does not exist:\n%s", calls)
	}
}

func TestPublishBuildsWithTheRevisionAndNoSecret(t *testing.T) {
	_, calls, err := runPublish(t, nil, "build", "site", rev)
	if err != nil {
		t.Fatalf("build: %v\n%s", err, calls)
	}
	want := "docker build --build-arg VERSION=" + rev +
		" --label org.opencontainers.image.revision=" + rev +
		" --label org.opencontainers.image.source=https://github.com/c4u-tech/c4u-telinhasegura-platform" +
		" -t telinhasegura-site:smoke site"
	if !strings.Contains(calls, want) {
		t.Errorf("calls lack %q:\n%s", want, calls)
	}
	if n := strings.Count(calls, "--build-arg"); n != 1 {
		t.Errorf("%d build arguments, want only VERSION", n)
	}
}

func TestPublishPushesBothTags(t *testing.T) {
	_, calls, err := runPublish(t, map[string]string{"REGISTRY": "registry.test/org"}, "push", "site", rev)
	if err != nil {
		t.Fatalf("push: %v\n%s", err, calls)
	}
	in := "registry.test/org/telinhasegura-site:in-" + siteDigest(t)
	for _, want := range []string{
		"docker tag telinhasegura-site:smoke " + in,
		"docker tag telinhasegura-site:smoke registry.test/org/telinhasegura-site:" + rev,
		"docker push " + in,
		"docker push registry.test/org/telinhasegura-site:" + rev,
	} {
		if !strings.Contains(calls, want) {
			t.Errorf("calls lack %q:\n%s", want, calls)
		}
	}
}

func TestPublishRefusesBadArguments(t *testing.T) {
	for _, args := range [][]string{{"build", "db", rev}, {"build", "site", "HEAD"}, {"deploy", "site", rev}, {"build", "site"}} {
		if _, calls, err := runPublish(t, nil, args...); err == nil {
			t.Errorf("%v succeeded:\n%s", args, calls)
		}
	}
}
