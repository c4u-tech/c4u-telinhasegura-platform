#!/bin/sh
# What a change affects: the Go modules, Dart packages, Ruby tooling and
# images that a pull request has to check, printed as GitHub step outputs:
#   go=<module dirs>  dart=<package dirs>  ruby=true|false
#   images=<some of: api web site backup>  full=true|false
# Module dirs carry a trailing slash, as the Makefile lists them, so CI can
# pass them straight to its targets.
#
# The change is what <head> adds since it left <base>: the diff from their
# merge base, so commits that reached the base branch in the meantime do
# not count. A file belongs to the nearest module above it. Files that
# every part depends on (workflows, scripts, root build files) and files
# no rule knows mean everything, so nothing a change can break goes
# unchecked; docs mean nothing. An image is affected when its build-input
# digest differs between the two commits; the backup image is smoke-tested
# against the API image, so it follows the API.
# --all prints everything, for pushes that run the whole gate.
# usage: scripts/affected.sh <base> <head> | scripts/affected.sh --all
set -eu
usage() { echo "usage: scripts/affected.sh <base> <head> | scripts/affected.sh --all" >&2; exit 2; }
here="$(cd "$(dirname "$0")" && pwd)"
cd "$(git rev-parse --show-toplevel)"

# modules <rev>: the dirs holding a tracked go.mod or pubspec.yaml, as
# "go <dir>/" or "dart <dir>/" lines ("./" for the root).
modules() {
  git ls-tree -r --name-only --full-tree "$1" | while IFS= read -r f; do
    case "$f" in
      go.mod) echo "go ./" ;;
      */go.mod) echo "go ${f%go.mod}" ;;
      pubspec.yaml) echo "dart ./" ;;
      */pubspec.yaml) echo "dart ${f%pubspec.yaml}" ;;
    esac
  done
}

# join <kind>: the dirs of that kind from stdin, sorted, on one line.
join() { awk -v k="$1" '$1 == k { print $2 }' | sort -u | tr '\n' ' ' | sed 's/ $//'; }

# owner <path>: the nearest module above the path, as "<kind> <dir>/".
owner() {
  printf '%s\n' "$mods" | awk -v p="$1" '
    $2 == "./" || index(p, $2) == 1 { if (length($2) > best) { best = length($2); line = $0 } }
    END { if (line != "") print line }'
}

full=false
if [ "${1:-}" = "--all" ]; then
  [ $# -eq 1 ] || usage
  head=HEAD
  full=true
else
  [ $# -eq 2 ] || usage
  head="$2"
  mb="$(git merge-base "$1" "$head")" || { echo "affected: no merge base of $1 and $head" >&2; exit 1; }
  before="$(modules "$mb")"
  after="$(modules "$head")"
  mods="$(printf '%s\n%s\n' "$before" "$after" | sort -u)"
  # A module that is gone can no longer be checked on its own; whatever
  # used it may now break anywhere.
  while IFS= read -r m; do
    [ -z "$m" ] || printf '%s\n' "$after" | grep -qxF "$m" || full=true
  done <<BEFORE
$before
BEFORE
fi

hits="go tools/repoconfig/"
ruby=false
if [ "$full" = false ]; then
  paths="$(git diff --name-only --no-renames "$mb" "$head")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$p" in
      .github/workflows/* | scripts/*) full=true; break ;;
      docs/* | .github/*) continue ;;
      */*) ;;
      # At the root only the docs and the license texts are inert.
      *.md | LICENSE*) continue ;;
      *) full=true; break ;;
    esac
    case "$p" in
      site/*) hits="$hits
go tools/sitecheck/"; continue ;;
      app/fastlane/* | app/Gemfile* | app/.ruby-version) ruby=true; continue ;;
      deploy/backup/*) continue ;;
      # The site's legal pages show this version, so the site check reads it.
      backend/internal/identity/terms.go) hits="$hits
go tools/sitecheck/" ;;
    esac
    o="$(owner "$p")"
    if [ -n "$o" ]; then
      hits="$hits
$o"
      continue
    fi
    case "$p" in
      *.md) continue ;;
    esac
    full=true
    break
  done <<PATHS
$paths
PATHS
fi

if [ "$full" = true ]; then
  hits="$(modules "$head")"
  ruby=true
  images="api web site backup"
else
  images=""
  for pair in api:backend web:app site:site backup:deploy/backup; do
    name="${pair%%:*}"
    ctx="${pair#*:}"
    a=none
    b=none
    if [ "$(git cat-file -t "$mb:$ctx" 2>/dev/null)" = tree ]; then a="$(sh "$here/image-digest.sh" "$ctx" "$mb")"; fi
    if [ "$(git cat-file -t "$head:$ctx" 2>/dev/null)" = tree ]; then b="$(sh "$here/image-digest.sh" "$ctx" "$head")"; fi
    if [ "$a" != "$b" ] || { [ "$name" = backup ] && [ "${images%%[ ]*}" = api ]; }; then
      images="${images:+$images }$name"
    fi
  done
fi

echo "go=$(printf '%s\n' "$hits" | join go)"
echo "dart=$(printf '%s\n' "$hits" | join dart)"
echo "ruby=$ruby"
echo "images=$images"
echo "full=$full"
