package main

import (
	"flag"
	"fmt"
	"io"
	"os"
)

func main() {
	os.Exit(run(".", os.Args[1:], os.Stdout))
}

// run checks the commits reachable from --head (default HEAD) and from
// none of the refs given as arguments. It returns 0 when every one is
// signed off, 1 when some are not, and 2 on a usage or git error.
func run(dir string, args []string, out io.Writer) int {
	fs := flag.NewFlagSet("dco", flag.ContinueOnError)
	fs.SetOutput(out)
	head := fs.String("head", "HEAD", "the revision whose new commits are checked")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	bad, err := Unsigned(dir, *head, fs.Args())
	if err != nil {
		fmt.Fprintln(out, "dco:", err)
		return 2
	}
	for _, c := range bad {
		fmt.Fprintf(out, "dco: %.12s %q has no Signed-off-by: by its author <%s> (commit with git commit -s)\n",
			c.SHA, c.Subject, c.AuthorEmail)
	}
	if len(bad) > 0 {
		fmt.Fprintf(out, "dco: %d commit(s) not signed off; see CONTRIBUTING.md, \"Developer Certificate of Origin\"\n", len(bad))
		return 1
	}
	fmt.Fprintln(out, "dco: every new commit is signed off")
	return 0
}
