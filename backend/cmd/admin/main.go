// Command admin grants and revokes the platform admin role, and resets a staff member's lost MFA factor, from the
// server. No route can do either.
// It runs against a database the API has already migrated.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

const usage = "usage: admin grant-admin <email> | admin revoke-admin <email> | admin reset-mfa <email>"

func main() {
	if err := run(context.Background(), os.Args[1:], os.Getenv, os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "admin:", err)
		os.Exit(1)
	}
}

// run prints the account ID it changed, never the email.
func run(ctx context.Context, args []string, getenv func(string) string, stdout io.Writer) error {
	if len(args) != 2 || args[0] != "grant-admin" && args[0] != "revoke-admin" && args[0] != "reset-mfa" {
		return errors.New(usage)
	}
	url := getenv("DATABASE_URL")
	if url == "" {
		return errors.New("DATABASE_URL is required")
	}
	pool, err := db.Open(ctx, url)
	if err != nil {
		return err
	}
	defer pool.Close()
	log := slog.New(slog.NewTextHandler(os.Stderr, nil))
	svc := staff.NewService(staff.Deps{
		Pool:  pool,
		Audit: audit.Store{Pool: pool, Now: time.Now, Log: log},
		Now:   time.Now,
	})
	if args[0] == "reset-mfa" {
		id, err := svc.ResetMFA(ctx, args[1])
		if err != nil {
			return err
		}
		fmt.Fprintf(stdout, "mfa reset for account %s\n", id)
		return nil
	}
	if args[0] == "grant-admin" {
		id, err := svc.GrantAdmin(ctx, args[1])
		if err != nil {
			return err
		}
		fmt.Fprintf(stdout, "admin granted to account %s\n", id)
		return nil
	}
	id, err := svc.RevokeAdmin(ctx, args[1])
	if err != nil {
		return err
	}
	fmt.Fprintf(stdout, "admin revoked from account %s\n", id)
	return nil
}
