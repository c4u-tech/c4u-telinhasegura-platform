#!/bin/sh
# The build-input digest of an image: a hash of the git index entries (mode, blob, path) of every
# tracked file under the build context, minus what the context's
# .dockerignore excludes. Equal digests mean equal build inputs, so the
# pipeline reuses the image instead of rebuilding it. The .dockerignore is
# the one list of exclusions: Docker reads it for the build, this script
# for the name.
# usage: scripts/image-digest.sh <context-dir>   (relative to the repo root)
set -eu
ctx="${1:?usage: scripts/image-digest.sh <context-dir>}"
ctx="${ctx%/}"
cd "$(git rev-parse --show-toplevel)"
[ -d "$ctx" ] || { echo "image-digest: no build context $ctx" >&2; exit 1; }

set -- "$ctx"
if [ -f "$ctx/.dockerignore" ]; then
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
  done <"$ctx/.dockerignore"
fi
entries="$(git ls-files -s -- "$@")" || { echo "image-digest: git ls-files failed for $ctx" >&2; exit 1; }
[ -n "$entries" ] || { echo "image-digest: no tracked files in $ctx" >&2; exit 1; }
printf '%s\n' "$entries" | git hash-object --stdin
