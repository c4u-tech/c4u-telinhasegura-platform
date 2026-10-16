package repoconfig

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The fakes log every call to $FAKE_LOG; the bucket is the directory
// $FAKE_S3/<bucket>/...; FAKE_* switches make a stage fail.
var backupFakes = map[string]string{
	"pg_dump": `#!/bin/sh
echo "pg_dump $*" >> "$FAKE_LOG"
if [ -n "${FAKE_PG_DUMP_FAIL:-}" ]; then printf 'PARTIAL'; echo 'pg_dump: error: connection lost' >&2; exit 1; fi
if [ -n "${FAKE_PG_DUMP_TERM:-}" ]; then kill -TERM "$(ps -o ppid= -p $PPID | tr -d ' ')"; sleep 1; fi
printf 'DUMP'
`,
	"age": `#!/bin/sh
echo "age $*" >> "$FAKE_LOG"
case "$1" in
  -r) if [ -n "${FAKE_AGE_FAIL:-}" ]; then cat >/dev/null; exit 1; fi; printf 'age:'; cat ;;
  -d) if [ -n "${FAKE_AGE_FAIL:-}" ]; then cat >/dev/null; exit 1; fi; sed 's/^age://' ;;
  *) echo "fake age: unexpected $*" >&2; exit 2 ;;
esac
`,
	"rclone": `#!/bin/sh
echo "rclone[${RCLONE_CONFIG_STORE_PROVIDER:-} ${RCLONE_CONFIG_STORE_ENDPOINT:-}] $*" >> "$FAKE_LOG"
p() { echo "$FAKE_S3/${1#store:}"; }
case "$1" in
  rcat) if [ -n "${FAKE_RCAT_FAIL:-}" ]; then cat >/dev/null; exit 1; fi; f="$(p "$2")"; mkdir -p "$(dirname "$f")"; cat > "$f" ;;
  copyto) case "$3" in *weekly/*) [ -z "${FAKE_COPY_FAIL:-}" ] || exit 1 ;; esac; d="$(p "$3")"; mkdir -p "$(dirname "$d")"; cp "$(p "$2")" "$d" ;;
  deletefile) if [ -n "${FAKE_NO_DELETE:-}" ]; then echo 'AccessDenied' >&2; exit 1; fi; rm -f "$(p "$2")" ;;
  lsf) if [ -n "${FAKE_LSF_FAIL:-}" ]; then exit 1; fi; d="$(p "$2")"; [ ! -d "$d" ] || ls "$d" ;;
  cat) if [ -n "${FAKE_CAT_FAIL:-}" ]; then exit 1; fi; cat "$(p "$2")" ;;
  *) echo "fake rclone: unexpected $*" >&2; exit 2 ;;
esac
`,
	"curl": `#!/bin/sh
for a; do last="$a"; done
echo "curl $last" >> "$FAKE_LOG"
`,
	"date": `#!/bin/sh
echo "date TZ=${TZ:-} $*" >> "$FAKE_LOG"
case "$*" in
  *%u*) echo "${FAKE_DOW:-3}" ;;
  *) echo "2026-10-11T0600Z" ;;
esac
`,
	"pg_restore": `#!/bin/sh
echo "pg_restore $*" >> "$FAKE_LOG"
cat > "$FAKE_RESTORED"
`,
	"supercronic": `#!/bin/sh
echo "supercronic $*" >> "$FAKE_LOG"
`,
}

func backupEnv() map[string]string {
	return map[string]string{
		"DATABASE_URL":                "postgres://app:dbsecret@db:5432/app",
		"AGE_RECIPIENT":               "age1recipient",
		"BACKUP_S3_ACCESS_KEY_ID":     "keyid-secret",
		"BACKUP_S3_SECRET_ACCESS_KEY": "s3secret",
		"BACKUP_BUCKET":               "backups",
		"BACKUP_HEARTBEAT_URL":        "https://hb.test/abc",
	}
}

type backupRun struct {
	out, log, s3, restored string
	err                    error
}

// runBackup runs deploy/backup/backup.sh with the fakes first on PATH and
// an environment built from scratch: only PATH, TMPDIR
// and env reach it. seed pre-populates the bucket.
func runBackup(t *testing.T, env map[string]string, seed map[string]string, args ...string) backupRun {
	t.Helper()
	root := t.TempDir()
	bin := filepath.Join(root, "bin")
	for name, body := range backupFakes {
		tree(t, bin, map[string]string{name: body})
		if err := os.Chmod(filepath.Join(bin, name), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	s3 := filepath.Join(root, "s3")
	if err := os.MkdirAll(s3, 0o755); err != nil {
		t.Fatal(err)
	}
	tree(t, s3, seed)
	r := backupRun{log: filepath.Join(root, "log"), s3: s3, restored: filepath.Join(root, "restored")}
	cmd := exec.Command("sh", append([]string{filepath.Join(Root(), "deploy", "backup", "backup.sh")}, args...)...)
	cmd.Env = []string{
		"PATH=" + bin + string(os.PathListSeparator) + os.Getenv("PATH"),
		"TMPDIR=" + t.TempDir(),
		"FAKE_LOG=" + r.log,
		"FAKE_S3=" + s3,
		"FAKE_RESTORED=" + r.restored,
	}
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	out, err := cmd.CombinedOutput()
	r.out, r.err = string(out), err
	return r
}

func (r backupRun) calls(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(r.log)
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	return string(b)
}

func (r backupRun) object(rel string) (string, bool) {
	b, err := os.ReadFile(filepath.Join(r.s3, "backups", rel))
	return string(b), err == nil
}

func (r backupRun) count(prefix string) int {
	entries, _ := os.ReadDir(filepath.Join(r.s3, "backups", prefix))
	return len(entries)
}

const dumpName = "2026-10-11T0600Z.dump.age"

func TestBackupWritesAnEncryptedDailyDumpAndPingsTheHeartbeat(t *testing.T) {
	r := runBackup(t, backupEnv(), nil, "run-once")
	if r.err != nil {
		t.Fatalf("run-once: %v\n%s", r.err, r.out)
	}
	if got, ok := r.object("daily/" + dumpName); !ok || got != "age:DUMP" {
		t.Errorf("daily/%s = %q (exists %v), want age:DUMP", dumpName, got, ok)
	}
	if n := r.count("incoming"); n != 0 {
		t.Errorf("incoming/ holds %d objects, want 0", n)
	}
	if n := r.count("weekly"); n != 0 {
		t.Errorf("a weekday wrote %d weekly objects", n)
	}
	calls := r.calls(t)
	if strings.Count(calls, "curl https://hb.test/abc\n") != 1 || strings.Contains(calls, "/fail") {
		t.Errorf("heartbeat calls:\n%s\nwant one success ping", calls)
	}
	for _, want := range []string{"pg_dump -Fc", "age -r age1recipient", "rclone[GCS https://storage.googleapis.com] rcat store:backups/incoming/" + dumpName,
		"rclone[GCS https://storage.googleapis.com] copyto store:backups/incoming/" + dumpName + " store:backups/daily/" + dumpName} {
		if !strings.Contains(calls, want) {
			t.Errorf("calls lack %q:\n%s", want, calls)
		}
	}
}

// A backup must not need a delete: a key that may only create and read
// objects is enough.
func TestBackupSucceedsWithAKeyThatCannotDelete(t *testing.T) {
	env := backupEnv()
	env["FAKE_NO_DELETE"] = "1"
	env["FAKE_DOW"] = "7"
	r := runBackup(t, env, nil, "run-once")
	if r.err != nil {
		t.Fatalf("run-once: %v\n%s", r.err, r.out)
	}
	for _, rel := range []string{"daily/" + dumpName, "weekly/" + dumpName} {
		if got, ok := r.object(rel); !ok || got != "age:DUMP" {
			t.Errorf("%s = %q (exists %v), want age:DUMP", rel, got, ok)
		}
	}
	if strings.Contains(r.out, "AccessDenied") {
		t.Errorf("a refused clean-up reached the output:\n%s", r.out)
	}
	if calls := r.calls(t); strings.Contains(calls, "/fail") {
		t.Errorf("a refused clean-up pinged /fail:\n%s", calls)
	}
}

func TestBackupCopiesSundaysToWeekly(t *testing.T) {
	env := backupEnv()
	env["FAKE_DOW"] = "7"
	r := runBackup(t, env, nil, "run-once")
	if r.err != nil {
		t.Fatalf("run-once: %v\n%s", r.err, r.out)
	}
	if got, ok := r.object("weekly/" + dumpName); !ok || got != "age:DUMP" {
		t.Errorf("weekly/%s = %q (exists %v), want age:DUMP", dumpName, got, ok)
	}
	if !strings.Contains(r.calls(t), "date TZ=America/Sao_Paulo +%u") {
		t.Errorf("the weekday was not read in America/Sao_Paulo:\n%s", r.calls(t))
	}
}

func TestBackupFailureLeavesNoObjectAndPingsFail(t *testing.T) {
	for stage, sw := range map[string]string{"pg_dump": "FAKE_PG_DUMP_FAIL", "age": "FAKE_AGE_FAIL", "upload": "FAKE_RCAT_FAIL"} {
		t.Run(stage, func(t *testing.T) {
			env := backupEnv()
			env[sw] = "1"
			env["FAKE_DOW"] = "7"
			r := runBackup(t, env, nil, "run-once")
			if r.err == nil {
				t.Fatalf("a failing %s exited 0:\n%s", stage, r.out)
			}
			for _, prefix := range []string{"daily", "weekly", "incoming"} {
				if n := r.count(prefix); n != 0 {
					t.Errorf("%s/ holds %d objects after a failed %s", prefix, n, stage)
				}
			}
			if calls := r.calls(t); !strings.Contains(calls, "curl https://hb.test/abc/fail\n") {
				t.Errorf("no failure ping:\n%s", calls)
			}
		})
	}
}

func TestBackupWeeklyCopyFailureIsAFailure(t *testing.T) {
	env := backupEnv()
	env["FAKE_DOW"] = "7"
	env["FAKE_COPY_FAIL"] = "1"
	r := runBackup(t, env, nil, "run-once")
	if r.err == nil || !strings.Contains(r.out, "weekly") {
		t.Fatalf("err %v, output %q; want a failure naming the weekly copy", r.err, r.out)
	}
	if _, ok := r.object("daily/" + dumpName); !ok {
		t.Error("the daily dump was lost with the weekly copy")
	}
	if !strings.Contains(r.calls(t), "curl https://hb.test/abc/fail\n") {
		t.Error("no failure ping")
	}
}

func TestBackupRequiresEveryVariable(t *testing.T) {
	for name := range backupEnv() {
		t.Run(name, func(t *testing.T) {
			env := backupEnv()
			delete(env, name)
			r := runBackup(t, env, nil, "run-once")
			if r.err == nil || !strings.Contains(r.out, name) {
				t.Fatalf("err %v, output %q; want a failure naming %s", r.err, r.out, name)
			}
			calls := r.calls(t)
			if strings.Contains(calls, "pg_dump") || strings.Contains(calls, "rclone") || strings.Contains(calls, "curl") {
				t.Errorf("contacted something before refusing:\n%s", calls)
			}
		})
	}
}

func TestBackupHonoursAPresetEndpoint(t *testing.T) {
	env := backupEnv()
	env["BACKUP_S3_ENDPOINT"] = "http://s3.test:8080"
	env["BACKUP_S3_PROVIDER"] = "Rclone"
	r := runBackup(t, env, nil, "run-once")
	if r.err != nil {
		t.Fatalf("run-once: %v\n%s", r.err, r.out)
	}
	if !strings.Contains(r.calls(t), "rclone[Rclone http://s3.test:8080] rcat") {
		t.Errorf("the preset endpoint did not win:\n%s", r.calls(t))
	}
}

func TestBackupOutputNeverCarriesASecret(t *testing.T) {
	failing := backupEnv()
	failing["FAKE_PG_DUMP_FAIL"] = "1"
	for name, env := range map[string]map[string]string{"success": backupEnv(), "failure": failing} {
		t.Run(name, func(t *testing.T) {
			r := runBackup(t, env, nil, "run-once")
			for _, secret := range []string{"dbsecret", backupEnv()["DATABASE_URL"], "keyid-secret", "s3secret"} {
				if strings.Contains(r.out, secret) {
					t.Errorf("output carries %q:\n%s", secret, r.out)
				}
			}
		})
	}
}

func TestBackupRunValidatesThenSchedules(t *testing.T) {
	r := runBackup(t, backupEnv(), nil, "run")
	if r.err != nil {
		t.Fatalf("run: %v\n%s", r.err, r.out)
	}
	if !strings.Contains(r.calls(t), "supercronic /etc/backup/crontab") {
		t.Errorf("supercronic was not started:\n%s", r.calls(t))
	}
	env := backupEnv()
	delete(env, "AGE_RECIPIENT")
	if r := runBackup(t, env, nil, "run"); r.err == nil || strings.Contains(r.calls(t), "supercronic") {
		t.Errorf("run started without AGE_RECIPIENT: %v\n%s", r.err, r.calls(t))
	}
}

func restoreEnv() map[string]string {
	env := backupEnv()
	delete(env, "DATABASE_URL")
	delete(env, "AGE_RECIPIENT")
	delete(env, "BACKUP_HEARTBEAT_URL")
	env["AGE_IDENTITY_FILE"] = "/run/age/identity"
	return env
}

var twoDumps = map[string]string{
	"backups/daily/2026-10-01T0600Z.dump.age": "age:OLD",
	"backups/daily/2026-10-11T0600Z.dump.age": "age:NEW",
}

func TestBackupRestoreLatestRestoresTheNewestDump(t *testing.T) {
	r := runBackup(t, restoreEnv(), twoDumps, "restore", "latest", "postgres://u:p@h/target")
	if r.err != nil {
		t.Fatalf("restore: %v\n%s", r.err, r.out)
	}
	if b, _ := os.ReadFile(r.restored); string(b) != "NEW" {
		t.Errorf("restored %q, want NEW", b)
	}
	calls := r.calls(t)
	for _, want := range []string{"age -d -i /run/age/identity", "pg_restore --no-owner --no-privileges --exit-on-error --dbname=postgres://u:p@h/target"} {
		if !strings.Contains(calls, want) {
			t.Errorf("calls lack %q:\n%s", want, calls)
		}
	}
}

func TestBackupRestoreANamedDump(t *testing.T) {
	r := runBackup(t, restoreEnv(), twoDumps, "restore", "2026-10-01T0600Z.dump.age", "postgres://h/target")
	if r.err != nil {
		t.Fatalf("restore: %v\n%s", r.err, r.out)
	}
	if b, _ := os.ReadFile(r.restored); string(b) != "OLD" {
		t.Errorf("restored %q, want OLD", b)
	}
}

func TestBackupRestoreFailsWithNoDump(t *testing.T) {
	r := runBackup(t, restoreEnv(), nil, "restore", "latest", "postgres://h/target")
	if r.err == nil || !strings.Contains(r.out, "no dump") {
		t.Errorf("err %v, output %q; want a failure saying there is no dump", r.err, r.out)
	}
}

func TestBackupRefusesAnUnknownCommand(t *testing.T) {
	if r := runBackup(t, backupEnv(), nil, "explode"); r.err == nil || !strings.Contains(r.out, "usage") {
		t.Errorf("err %v, output %q; want a usage failure", r.err, r.out)
	}
}

func TestBackupRestoreFailsWhenAStageFails(t *testing.T) {
	for stage, sw := range map[string]string{"age": "FAKE_AGE_FAIL", "cat": "FAKE_CAT_FAIL"} {
		t.Run(stage, func(t *testing.T) {
			env := restoreEnv()
			env[sw] = "1"
			r := runBackup(t, env, twoDumps, "restore", "latest", "postgres://h/target")
			want := "the restore of daily/" + dumpName + " failed"
			if r.err == nil || !strings.Contains(r.out, want) {
				t.Errorf("err %v, output %q; want a failure saying %q", r.err, r.out, want)
			}
		})
	}
}

func TestBackupRestoreSaysWhenItCannotListTheBucket(t *testing.T) {
	env := restoreEnv()
	env["FAKE_LSF_FAIL"] = "1"
	r := runBackup(t, env, twoDumps, "restore", "latest", "postgres://h/target")
	if r.err == nil || !strings.Contains(r.out, "could not list") || strings.Contains(r.out, "no dump") {
		t.Errorf("err %v, output %q; want a could-not-list failure, not no-dump", r.err, r.out)
	}
}

func TestBackupFailsWhenTheStatusDirectoryCannotBeMade(t *testing.T) {
	env := backupEnv()
	env["TMPDIR"] = "/nonexistent-tmpdir" // mktemp -d fails; runBackup's own TMPDIR comes first
	r := runBackup(t, env, nil, "run-once")
	if r.err == nil || !strings.Contains(r.calls(t), "curl https://hb.test/abc/fail\n") {
		t.Errorf("err %v; want a failure and a failure ping\n%s", r.err, r.calls(t))
	}
}

// A TERM mid-dump (a container stop) must still delete incoming/ and ping
// /fail. The fake pg_dump signals the script, its grandparent.
func TestBackupTermMidDumpPingsFailAndCleansUp(t *testing.T) {
	if _, err := exec.LookPath("ps"); err != nil {
		t.Skip("no ps")
	}
	env := backupEnv()
	env["FAKE_PG_DUMP_TERM"] = "1"
	r := runBackup(t, env, nil, "run-once")
	if r.err == nil {
		t.Fatalf("a TERMed backup exited 0:\n%s", r.out)
	}
	for _, prefix := range []string{"daily", "incoming"} {
		if n := r.count(prefix); n != 0 {
			t.Errorf("%s/ holds %d objects after TERM", prefix, n)
		}
	}
	if calls := r.calls(t); !strings.Contains(calls, "curl https://hb.test/abc/fail\n") {
		t.Errorf("no failure ping:\n%s", calls)
	}
}
