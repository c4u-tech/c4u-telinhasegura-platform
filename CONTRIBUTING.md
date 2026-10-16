# Contributing to Telinha Segura

Thank you for helping. Telinha Segura is a platform of curated, child-safe
content: an app (mobile and web) with parental controls, where children
watch only YouTube videos the community has screened as suitable. The
[README](README.md#principles) lists the principles every change keeps.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

Open an issue with the proposal form before any large change, so we agree
on the direction before you write code. Small fixes can go straight to a
pull request.

Security issues never go in a public issue or a pull request: see
[SECURITY.md](SECURITY.md).

## Set up

```sh
make doctor        # checks your machine and tells you the fix for what is missing
make api           # Postgres and the Go API on http://localhost:8080
make run-android   # the app on the Android emulator
make run-ios       # the app on the iOS simulator
```

The full runbooks, from a fresh Mac to the app running, are in
[docs/development/](docs/development/README.md).

## The gate

`make check` is the done bar and exactly what CI runs: formatting, static
analysis, tests and build for every Go module and Dart/Flutter package.
`make fast` is the quick subset (format and static analysis, no tests) to
run while you work.

## How we work

- [Conventional Commits](https://www.conventionalcommits.org/). CI lints
  the pull request title, which becomes the squash commit.
- Branch off `dev` with a short-lived branch, open a pull request into
  `dev` with green CI, and it is squash-merged. `dev` is promoted to `stg`
  and `stg` to `prd` by merge commit, never a squash; releases are tagged
  per component on `prd`.
- One self-contained change per pull request, of at most about 400
  changed lines. If a pull request does two things, split it.

## Tests

Code that carries behaviour is written test first: write a failing test,
see it fail for the reason you expect, write the least code that passes
it, then refactor with the test green. Copy the closest existing test
rather than inventing a new harness:

| Layer | Start from |
| ----- | ---------- |
| Go unit | `backend/internal/platform/secret/secret_test.go` |
| Go with Postgres | `backend/internal/platform/db/db_test.go` (`dbtest.New(t)` gives an isolated migrated schema; it skips without `TEST_DATABASE_URL`) |
| Go HTTP | `backend/internal/httpapi/health_test.go` |
| Shell script | `tools/repoconfig/back_merge_test.go` |
| Dart unit | `app/test/auth/api_client_test.dart` |
| Flutter screen | `app/test/access/email_sign_in_test.dart` |
| Flutter accessibility | `app/test/access/a11y_test.dart` |

## Developer Certificate of Origin

Every commit must be signed off, certifying the Developer Certificate of
Origin 1.1 (<https://developercertificate.org/>):

> Developer Certificate of Origin
> Version 1.1
>
> Copyright (C) 2004, 2006 The Linux Foundation and its contributors.
>
> Everyone is permitted to copy and distribute verbatim copies of this
> license document, but changing it is not allowed.
>
> Developer's Certificate of Origin 1.1
>
> By making a contribution to this project, I certify that:
>
> (a) The contribution was created in whole or in part by me and I
>     have the right to submit it under the open source license
>     indicated in the file; or
>
> (b) The contribution is based upon previous work that, to the best
>     of my knowledge, is covered under an appropriate open source
>     license and I have the right under that license to submit that
>     work with modifications, whether created in whole or in part
>     by me, under the same open source license (unless I am
>     permitted to submit under a different license), as indicated
>     in the file; or
>
> (c) The contribution was provided directly to me by some other
>     person who certified (a), (b) or (c) and I have not modified
>     it.
>
> (d) I understand and agree that this project and the contribution
>     are public and that a record of the contribution (including all
>     personal information I submit with it, including my sign-off) is
>     maintained indefinitely and may be redistributed consistent with
>     this project or the open source license(s) involved.

Signing off is a line at the end of the commit message. `git commit -s`
adds it:

```text
Signed-off-by: Your Name <you@example.com>
```

The email must match the commit's author email.

If you missed a sign-off, fix the last commit with
`git commit --amend -s --no-edit`, or a whole branch with
`git fetch origin && git rebase --signoff origin/dev`. CI's `dco` job checks
every new commit. Merge commits and bot commits are exempt; keep merges out
of your branch by rebasing on `origin/dev` instead.

## License

Your contributions are licensed under AGPL-3.0-only with the app-store
permission: see [COPYRIGHT.md](COPYRIGHT.md) and
[LICENSE-EXCEPTION.md](LICENSE-EXCEPTION.md). The project's names and marks
are not licensed: see [TRADEMARKS.md](TRADEMARKS.md).
