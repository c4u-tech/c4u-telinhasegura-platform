<!-- Title must be a Conventional Commit. Into dev: squash-merge (the title becomes the commit). Promotions dev → stg → prd and back-merges: merge commit, never squash. -->

## What

<!-- One self-contained change. If this PR does two things, split it. -->

## Why

<!-- Link the issue that motivated it. -->

## Checklist

- [ ] `make check` green
- [ ] Every commit signed off (`git commit -s`, DCO)
- [ ] ≤400 changed lines (or a stated reason why not)
- [ ] Tests written first (TDD red step exists in history)
