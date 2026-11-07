#!/bin/sh
# The build-input digest of an image: a hash of the git index entries (mode, blob, path) of every
# tracked file under the build context, minus what the context's
# .dockerignore excludes. Equal digests mean equal build inputs, so the
# pipeline reuses the image instead of rebuilding it. The .dockerignore is
# the one list of exclusions: Docker reads it for the build, this script
# for the name.
# Given a revision, it hashes the files of that commit instead, with that
# commit's .dockerignore, without checking it out; on a clean tree the
# digest of HEAD equals the digest of the index.
# usage: scripts/image-digest.sh <context-dir> [<rev>]   (relative to the repo root)
set -eu
ctx="${1:?usage: scripts/image-digest.sh <context-dir> [<rev>]}"
ctx="${ctx%/}"
rev="${2:-}"
cd "$(git rev-parse --show-toplevel)"
if [ -n "$rev" ]; then
  [ "$(git cat-file -t "$rev:$ctx" 2>/dev/null)" = tree ] ||
    { echo "image-digest: no build context $ctx at $rev" >&2; exit 1; }
  if git cat-file -e "$rev:$ctx/.dockerignore" 2>/dev/null; then
    ignore="$(git show "$rev:$ctx/.dockerignore")"
  else
    ignore=""
  fi
else
  [ -d "$ctx" ] || { echo "image-digest: no build context $ctx" >&2; exit 1; }
  if [ -f "$ctx/.dockerignore" ]; then ignore="$(cat "$ctx/.dockerignore")"; else ignore=""; fi
fi

set -- "$ctx"
while IFS= read -r line || [ -n "$line" ]; do
  line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$line" in
    "" | "#"*) continue ;;
    "!"*)
      echo "image-digest: $ctx/.dockerignore: negated patterns are not supported ($line)" >&2
      exit 1 ;;
  esac
  line="${line#/}"
  line="${line%/}"
  # A pattern names a file, or a directory and everything under it.
  set -- "$@" ":(exclude,glob)$ctx/$line" ":(exclude,glob)$ctx/$line/**"
done <<IGNORE
$ignore
IGNORE

if [ -n "$rev" ]; then
  # A throwaway index holding the commit's tree lists its files in the
  # same form, with the same pathspecs, as the real index does.
  index="$(mktemp)"
  trap 'rm -f "$index"' EXIT
  GIT_INDEX_FILE="$index" git read-tree "$rev" ||
    { echo "image-digest: cannot read $rev" >&2; exit 1; }
  entries="$(GIT_INDEX_FILE="$index" git ls-files -s -- "$@")" ||
    { echo "image-digest: git ls-files failed for $ctx" >&2; exit 1; }
else
  entries="$(git ls-files -s -- "$@")" || { echo "image-digest: git ls-files failed for $ctx" >&2; exit 1; }
fi
[ -n "$entries" ] || { echo "image-digest: no tracked files in $ctx" >&2; exit 1; }
printf '%s\n' "$entries" | git hash-object --stdin
