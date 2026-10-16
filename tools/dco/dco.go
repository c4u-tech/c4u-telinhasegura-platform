// Command dco fails when a commit new to the repository lacks a Developer
// Certificate of Origin sign-off by its own author. "New" means reachable
// from the PR head and from none of the environment branches, so
// promotions and back-merges, whose commits were all accepted before, have
// nothing to check.
package main

import (
	"fmt"
	"os/exec"
	"regexp"
	"strings"
)

// Commit is one commit as git log reports it.
type Commit struct {
	SHA, Subject, AuthorName, AuthorEmail, Body string
	Parents                                     int
}

var signOff = regexp.MustCompile(`(?m)^Signed-off-by: .+ <([^<>]+)>\s*$`)

// signed reports whether the body carries a sign-off by the author.
func (c Commit) signed() bool {
	for _, m := range signOff.FindAllStringSubmatch(c.Body, -1) {
		if strings.EqualFold(m[1], c.AuthorEmail) {
			return true
		}
	}
	return false
}

// botEmail is the noreply address the platform gives every App and bot
// account: a numeric id, a plus sign, then the bot's name.
var botEmail = regexp.MustCompile(`^\d+\+[^@]+\[bot\]@users\.noreply\.github\.com$`)

// exempt covers merge commits, which add no authored change of their own,
// and bot commits (release-please's App, the Actions bot). A bot needs both
// a name ending in [bot] and the bot noreply address, because anyone can set
// user.name to anything.
func (c Commit) exempt() bool {
	if c.Parents > 1 {
		return true
	}
	return strings.HasSuffix(c.AuthorName, "[bot]") && botEmail.MatchString(c.AuthorEmail)
}

// Unsigned returns the commits reachable from head and from none of
// exclude that need a sign-off and lack one, oldest first.
func Unsigned(dir, head string, exclude []string) ([]Commit, error) {
	args := []string{"log", "--reverse", "--format=%H%x00%s%x00%an%x00%ae%x00%P%x00%B%x1e", head}
	if len(exclude) > 0 {
		args = append(append(args, "--not"), exclude...)
	}
	args = append(args, "--")
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok {
			return nil, fmt.Errorf("git log: %v: %s", err, strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, fmt.Errorf("git log: %v", err)
	}
	var bad []Commit
	for _, rec := range strings.Split(string(out), "\x1e") {
		rec = strings.TrimLeft(rec, "\n")
		if rec == "" {
			continue
		}
		f := strings.SplitN(rec, "\x00", 6)
		if len(f) != 6 {
			return nil, fmt.Errorf("git log: malformed record %q", rec)
		}
		c := Commit{SHA: f[0], Subject: f[1], AuthorName: f[2], AuthorEmail: f[3],
			Parents: len(strings.Fields(f[4])), Body: f[5]}
		if !c.exempt() && !c.signed() {
			bad = append(bad, c)
		}
	}
	return bad, nil
}
