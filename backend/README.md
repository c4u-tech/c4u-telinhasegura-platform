# backend

The Go API. Gates run from the repository root: `make check`.

## Postgres for tests and local runs

```bash
docker run -d --name ts-pg -e POSTGRES_PASSWORD=postgres -p 55432:5432 postgres:17
export TEST_DATABASE_URL="postgres://postgres:postgres@localhost:$(docker port ts-pg 5432/tcp | sed -n 's/.*:\([0-9][0-9]*\)$/\1/p' | head -n1)/postgres?sslmode=disable"
```

Port 55432 keeps `ts-pg` clear of another Postgres on 5432.
`TEST_DATABASE_URL` follows whatever port `ts-pg` publishes, so an older
`ts-pg` on 5432 still works. `make api` creates the same container.

Without `TEST_DATABASE_URL`, Postgres tests skip locally and fail in CI.

## Running the API

From the repository root, `make api` starts `ts-pg` and the API together,
reaching Postgres on whatever port `ts-pg` publishes (another project's
Postgres may hold 5432). By hand:

```bash
DATABASE_URL="$TEST_DATABASE_URL" APP_BASE_URL=http://localhost:5000 \
ALLOWED_ORIGINS=http://localhost:5000 go run ./cmd/api
```

Google and Apple sign-in are off until their client IDs are set:

- `GOOGLE_CLIENT_IDS`: comma-separated accepted `aud` values (the web
  client ID, which Android and iOS use as `serverClientId`).
- `APPLE_CLIENT_IDS`: comma-separated; the iOS bundle ID and the
  Services ID used on Android and the web.
- `APP_ANDROID_PACKAGE`: required with Apple; the Android app that
  `POST /v1/oauth/apple/callback` redirects to.
- `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY`: required with
  `APPLE_CLIENT_IDS`. They sign the client secret the API uses to revoke
  a Sign in with Apple authorization when an Apple-linked account is
  deleted. The key is the `.p8` file, on one line with `\n` escapes
  accepted; rotate it by revoking the key in the Apple Developer portal.

Behind a reverse proxy, set `TRUSTED_PROXIES` to the
proxy's network: a comma-separated list of CIDRs or addresses. Only a peer
inside it has its `X-Forwarded-For` read, from the right, skipping listed
addresses, so the per-IP limits key on the client. List only the proxy's
own network: a range as wide as `0.0.0.0/0` hands the key to the client.
Unset (the default), the limits key on the TCP peer. A malformed entry
stops the API from starting.

Email. Every message goes to the `mail_outbox` table and a
worker in the API delivers it every `MAIL_POLL_INTERVAL` (default `5s`,
from `1s` to `1m`), retrying transient failures and dropping a message
once its link has expired.

- `SMTP_HOST`: unset (the default), the worker writes each message as an
  `.eml` file under `MAIL_DIR` (default `tmp/mail`); open them with any
  mail client. Set, it delivers over SMTP and requires the three below.
- `SMTP_PORT` (default `587`, STARTTLS; `465` is implicit TLS). TLS is
  mandatory and verified.
- `SMTP_USERNAME`, `SMTP_PASSWORD`: the provider's SMTP credential.
  Never logged.
- `MAIL_FROM`: the sender mailbox, for example
  `Telinha Segura <noreply@coding4u.tech>`.
- `MAIL_ALLOWED_RECIPIENTS`: optional, comma-separated addresses and
  `@domain` entries; any other recipient is suppressed. Set it on
  staging; leave it empty in production.

Curation:

- `YOUTUBE_API_KEY`: the YouTube Data API key; while empty, a suggestion
  that needs a YouTube call answers `503 video_source_unavailable` (Shorts
  links and videos already stored are still answered). Never logged.
- `CURATION_MIN_APPROVALS` (default 2), `CURATION_MAX_DURATION`
  (default `20m`) and `CURATION_REVISIT_DAYS` (default 180).
- `CATALOG_SHELF_SIZE` (default 12, at most 50): videos per theme on a
  child's shelf. `CURATION_REPORT_THRESHOLD` (default 3): distinct
  families whose reports hold a video for the admin.
- `PACK_MAX_DURATION` (default `20m`): the longest total a pacotinho's
  videos may run. `PACK_ROW_SIZE` (default 6, from 1 to 12): pacotinhos in
  a child's row, chosen by the daily rotation.

Privileged MFA:

- `STAFF_MFA_KEY`: 32 random bytes in standard base64
  (`openssl rand -base64 32`) that seal the staff TOTP secrets. Never
  logged. While empty, the MFA routes answer `503 mfa_unavailable` and
  nothing else changes. A set but malformed value stops the API from
  starting. Losing it makes every factor unusable: reset
  each staff member with `go run ./cmd/admin reset-mfa <email>`.
- `STAFF_MFA_REQUIRED` (default on; off only when exactly `false`):
  admin and moderator routes refuse a session that has not passed the
  challenge in the last 30 minutes. While on, it needs `STAFF_MFA_KEY`,
  or the API refuses to start. `make api` keeps a local key in
  `backend/tmp/staff-mfa.key`, made on its first run.

Health:

- `GET /livez`: the process answers, with no I/O, and reports the build
  (`{"version":"<sha>"}`, `dev` in a local build). The container's
  `HEALTHCHECK` runs `api healthcheck`, which asks it on
  `127.0.0.1:<HTTP_ADDR port>` with a 2 s timeout.
- `GET /healthz`: 200 when the database answers a ping within 2 s, else
  `503 unavailable`. For outside monitoring, never for the container's
  healthcheck: a database blip must not restart the API.

Hosted values per environment are set in the deployment platform, never
in the repository.

## Migrations

Numbered `.sql` files in `internal/platform/db/migrations`, applied at
startup under an advisory lock, forward-only. Every migration
must keep the previous release working (expand/contract): add tables,
nullable columns and indexes; drop or rename a column, or tighten a
constraint, only in a later release that no running release still reads.
Every migration runs in a transaction, so an index is a plain `CREATE
INDEX` that blocks writes to its table while it builds: fine on a small
table, while an index on a large one needs a non-transactional path,
decided when that need arises. A migration must finish within about 50
seconds: the image's healthcheck (20 s start period, then three 10 s
retries) gets a starting task replaced after that, rolling the migration
back and looping the rollout; a longer one needs a raised start period or
a separate path. The API needs a direct connection to Postgres, not a
transaction-mode pooler.

## Container image

`backend/Dockerfile` builds `api` (the entrypoint) and `admin` into a
distroless, non-root image; `VERSION` sets what `/livez`
reports. From the repository root:

```bash
docker build --build-arg VERSION=$(git rev-parse HEAD) -t telinhasegura-api backend
DATABASE_URL="postgres://postgres:postgres@host.docker.internal:55432/postgres?sslmode=disable" \
  sh scripts/image-smoke.sh telinhasegura-api "$(git rev-parse HEAD)"
```

The admin tool runs in the same image: `docker run --rm -e DATABASE_URL
--entrypoint /admin telinhasegura-api grant-admin <email>`.

## Platform admin

The admin role is granted only from the server, never through the API.
With the API's database migrated:

```bash
DATABASE_URL="$TEST_DATABASE_URL" go run ./cmd/admin grant-admin <email>
DATABASE_URL="$TEST_DATABASE_URL" go run ./cmd/admin revoke-admin <email>
```

Both print the account ID and exit non-zero for an unknown email.
