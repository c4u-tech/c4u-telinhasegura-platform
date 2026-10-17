// Command api serves the Telinha Segura HTTP API.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/config"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/curation"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/family"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/httpapi"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/identity"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/parental"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/appleid"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/audit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/db"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/idtoken"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/mail"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/ratelimit"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/platform/sweep"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/privacy"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/screentime"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/session"
	"github.com/c4u-tech/c4u-telinhasegura-platform/backend/internal/staff"
)

// version is the build, set with -ldflags "-X main.version=<sha>" and
// reported by /livez.
var version = "dev"

const usage = "usage: api | api healthcheck"

func main() {
	cmd, err := command(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	if cmd == "healthcheck" {
		if err := healthcheck(context.Background(), os.Getenv); err != nil {
			fmt.Fprintln(os.Stderr, "api healthcheck:", err)
			os.Exit(1)
		}
		return
	}
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := serve(log); err != nil {
		log.Error("api stopped", "err", err)
		os.Exit(1)
	}
}

// command reads the arguments: none serves the API, "healthcheck" probes it.
func command(args []string) (string, error) {
	switch {
	case len(args) == 0:
		return "serve", nil
	case len(args) == 1 && args[0] == "healthcheck":
		return "healthcheck", nil
	}
	return "", errors.New(usage)
}

// healthcheck is the container's HEALTHCHECK: distroless has no shell or
// curl, so the binary asks its own /livez. It
// reads only HTTP_ADDR.
func healthcheck(ctx context.Context, getenv func(string) string) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, probeURL(getenv), nil)
	if err != nil {
		return err
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("/livez answered %d", res.StatusCode)
	}
	return nil
}

// probeURL is /livez on the loopback, at HTTP_ADDR's port (default 8080).
func probeURL(getenv func(string) string) string {
	port := "8080"
	if _, p, err := net.SplitHostPort(getenv("HTTP_ADDR")); err == nil && p != "" {
		port = p
	}
	return "http://127.0.0.1:" + port + "/livez"
}

func serve(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load(os.Getenv)
	if err != nil {
		return err
	}
	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		return err
	}

	now := time.Now
	outbox := mail.Outbox{Pool: pool, Now: now} // every service enqueues; the worker below delivers
	idTokens := idtoken.NewOIDC(&http.Client{Timeout: 5 * time.Second}, now, map[idtoken.Provider]idtoken.ProviderConfig{
		idtoken.Google: idtoken.GoogleConfig(cfg.GoogleClientIDs),
		idtoken.Apple:  idtoken.AppleConfig(cfg.AppleClientIDs),
	})
	auditStore := audit.Store{Pool: pool, Now: now, Log: log}
	var breaches identity.BreachChecker
	if cfg.HIBPEnabled {
		breaches = identity.HIBP{Client: &http.Client{Timeout: 3 * time.Second}, BaseURL: identity.HIBPBaseURL}
	}
	sessions := &session.Service{Pool: pool, Audit: auditStore, Now: now}
	ids := identity.NewService(identity.Deps{
		Store:      identity.Store{Pool: pool},
		Policy:     identity.PasswordPolicy{Breaches: breaches, Log: log},
		Hash:       identity.DefaultHashParams,
		Mail:       outbox,
		Audit:      auditStore,
		Sessions:   sessions,
		IDTokens:   idTokens,
		Now:        now,
		AppBaseURL: cfg.AppBaseURL,
	})
	fam := family.NewService(family.Deps{
		Pool:          pool,
		Mail:          outbox,
		Audit:         auditStore,
		Now:           now,
		AppBaseURL:    cfg.AppBaseURL,
		InviteLimiter: ratelimit.New(20, 24*time.Hour, now),
		TokenLimiter:  ratelimit.New(10, time.Minute, now),
		Log:           log,
	})
	par := parental.NewService(parental.Deps{
		Pool:           pool,
		Mail:           outbox,
		Audit:          auditStore,
		Now:            now,
		Hash:           identity.DefaultHashParams,
		AppBaseURL:     cfg.AppBaseURL,
		CodeLimiter:    ratelimit.New(20, time.Hour, now),
		Log:            log,
		ConsentVersion: family.ConsentPolicyVersion,
	})
	var videos curation.VideoSource // nil while YOUTUBE_API_KEY is empty: a YouTube call answers 503
	if cfg.YouTubeAPIKey != "" {
		videos = curation.YouTube{
			Client: &http.Client{
				Timeout: 5 * time.Second,
				// The key rides in the query: never follow a redirect off-host.
				CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
			},
			BaseURL: curation.YouTubeBaseURL,
			Key:     cfg.YouTubeAPIKey,
		}
	}
	thumbs := curation.YouTubeThumbs{
		Client: &http.Client{
			Timeout: 5 * time.Second,
			// A redirect off the image host is a failure, never followed.
			CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
		},
		BaseURL: curation.ThumbBaseURL,
	}
	cur := curation.NewService(curation.Deps{
		Pool:              pool,
		Audit:             auditStore,
		Now:               now,
		Source:            videos,
		SuggestLimiter:    ratelimit.New(10, 24*time.Hour, now),
		MinApprovals:      cfg.CurationMinApprovals,
		MaxDuration:       cfg.CurationMaxDuration,
		RevisitAfter:      time.Duration(cfg.CurationRevisitDays) * 24 * time.Hour,
		Thumbs:            thumbs,
		ShelfSize:         cfg.CatalogShelfSize,
		PackMaxDuration:   cfg.PackMaxDuration,
		PackRowSize:       cfg.PackRowSize,
		ReportLimiter:     ratelimit.New(20, 24*time.Hour, now),
		ReportThreshold:   cfg.CurationReportThreshold,
		CheckVideoLimiter: ratelimit.New(1, time.Hour, now),
		CheckChildLimiter: ratelimit.New(10, time.Hour, now),
		Log:               log,
	})
	st := screentime.NewService(screentime.Deps{Pool: pool, Audit: auditStore, Now: now, BeatLimiter: ratelimit.New(20, time.Minute, now), PlayLimiter: ratelimit.New(30, time.Minute, now)})
	stf := staff.NewService(staff.Deps{Pool: pool, Audit: auditStore, Now: now, MFAKey: cfg.StaffMFAKey,
		Mail: outbox, Log: log, // the suspension notices
		Accounts: ids, Sessions: sessions, Families: fam, Devices: par, Content: cur, AuditLog: auditStore,
		LookupLimiter: ratelimit.New(30, time.Hour, now),
		ResetLimiter:  ratelimit.New(3, time.Hour, now),
	})
	// nil when Apple is off: nothing to revoke.
	var appleRevoker privacy.AppleRevoker
	if len(cfg.AppleClientIDs) > 0 {
		appleRevoker = &appleid.Client{HTTP: &http.Client{Timeout: 15 * time.Second}, TeamID: cfg.AppleTeamID, KeyID: cfg.AppleKeyID, Key: cfg.AppleKey, Now: now}
	}
	srv := &httpapi.Server{
		Pool:           pool,
		AllowedOrigins: cfg.AllowedOrigins,
		Log:            log,
		Identity:       ids,
		Sessions:       sessions,
		Family:         fam,
		Parental:       par,
		Privacy: privacy.NewService(privacy.Deps{
			Pool:          pool,
			Mail:          outbox,
			Audit:         auditStore,
			Now:           now,
			ExportLimiter: ratelimit.New(5, time.Hour, now),
			Log:           log,
			IDTokens:      idTokens,
			Apple:         appleRevoker,
		}),
		Curation:         cur,
		Staff:            stf,
		StaffMFARequired: cfg.StaffMFARequired,
		ScreenTime:       st,
		IPLimiter:        ratelimit.New(30, time.Minute, now),
		RedeemLimiter:    ratelimit.New(10, time.Minute, now),
		TrustedProxies:   cfg.TrustedProxies,
		Version:          version,
	}
	if len(cfg.AppleClientIDs) > 0 {
		srv.AppleAndroidPackage = cfg.AndroidPackage
	}

	ticker := time.NewTicker(cfg.SweepInterval)
	defer ticker.Stop()
	go sweep.Run(ctx, ticker.C, log,
		sweep.Job{Name: "screentime_retention", Run: st.Sweep},
		sweep.Job{Name: "youtube_refresh", Run: cur.RefreshSources},
		sweep.Job{Name: "thumbnail_expiry", Run: cur.ExpireThumbnails},
		sweep.Job{Name: "mail_cleanup", Run: outbox.Cleanup},
	)
	mailTicker := time.NewTicker(cfg.MailPollInterval)
	defer mailTicker.Stop()
	worker := mail.Worker{Pool: pool, Sender: mailSink(cfg, log), Now: now, Log: log, Allowed: cfg.MailAllowed}
	mailDone := make(chan struct{})
	go func() {
		defer close(mailDone)
		sweep.Run(ctx, mailTicker.C, log, sweep.Job{Name: "mail", Run: worker.Drain})
	}()

	hs := &http.Server{Addr: cfg.Addr, Handler: srv.Handler(), ReadHeaderTimeout: 10 * time.Second}
	drained := make(chan error, 1)
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		drained <- hs.Shutdown(shutdown)
	}()
	log.Info("api listening", "addr", cfg.Addr)
	if err := hs.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	// ListenAndServe returns as soon as Shutdown starts; wait for the drain
	// so in-flight requests finish before the pool closes.
	drainErr := <-drained
	// A send in flight is never cut mid-way: the pool closes after it.
	if waitFor(mailDone, mail.ShutdownGrace) {
		log.Info("mail: worker stopped")
	} else {
		log.Warn("mail: worker still sending at shutdown; the lease will retry it")
	}
	return drainErr
}

// waitFor reports whether done closed within d.
func waitFor(done <-chan struct{}, d time.Duration) bool {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-done:
		return true
	case <-t.C:
		return false
	}
}
