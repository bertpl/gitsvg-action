#!/usr/bin/env bash
#
# Cut a release of gitsvg-action.
#
# Usage:
#   scripts/release.sh X.Y.Z
#
# Steps, in order:
#   1. Validate the working tree: clean, on main, in sync with origin/main.
#   2. Finalize CHANGELOG.md — turn the "## [Unreleased]" section into a dated
#      "## [X.Y.Z]" section.
#   3. Commit, tag vX.Y.Z, and push main + the tag.
#   4. Create the GitHub Release from that changelog section.
#
# Pushing the tag triggers .github/workflows/release.yml, which re-points the
# moving "v1" major tag at the new release.
#
# Not automated (UI-only): ticking "Publish this Action to the GitHub
# Marketplace" on the release, which refreshes the Marketplace listing.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

readonly CHANGELOG="CHANGELOG.md"

die()  { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

# --- parse + validate the version -----------------
version="${1:-}"
[ -n "$version" ] || die "usage: scripts/release.sh X.Y.Z"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "version must be X.Y.Z, got '$version'"
tag="v$version"

# --- pre-flight checks ----------------------------
command -v gh >/dev/null 2>&1 || die "gh CLI not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"

[ "$(git branch --show-current)" = "main" ] || die "not on main"
git diff --quiet && git diff --cached --quiet || die "working tree is dirty"

info "fetching origin"
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
  || die "local main is out of sync with origin/main"

if git rev-parse "$tag" >/dev/null 2>&1; then
  die "tag $tag already exists"
fi

grep -q '^## \[Unreleased\]' "$CHANGELOG" || die "no '## [Unreleased]' section in $CHANGELOG"

unreleased_body="$(awk '
  /^## \[Unreleased\]/ { capturing = 1; next }
  capturing && /^## \[/ { exit }
  capturing { print }
' "$CHANGELOG" | sed '/^[[:space:]]*$/d')"
[ -n "$unreleased_body" ] || die "'## [Unreleased]' is empty — nothing to release"

# --- finalize the changelog -----------------------
today="$(date +%Y-%m-%d)"
info "finalizing $CHANGELOG: [Unreleased] -> [$version] - $today"
awk -v ver="$version" -v date="$today" '
  !inserted && /^## \[Unreleased\]/ {
    print
    print ""
    print "## [" ver "] - " date
    inserted = 1
    next
  }
  { print }
' "$CHANGELOG" > "$CHANGELOG.tmp"
mv "$CHANGELOG.tmp" "$CHANGELOG"

# --- commit, tag, push ----------------------------
info "committing + tagging $tag"
git add "$CHANGELOG"
git commit --quiet -m "chore: release $tag"
git tag "$tag"

info "pushing main + $tag"
git push --quiet origin main
git push --quiet origin "$tag"

# --- create the GitHub Release --------------------
notes="$(awk -v ver="$version" '
  $0 ~ "^## \\[" ver "\\]" { capturing = 1; next }
  capturing && /^## \[/ { exit }
  capturing { print }
' "$CHANGELOG")"

info "creating GitHub Release $tag"
gh release create "$tag" --title "$tag" --notes "$notes"

info "done — release.yml will re-point v1 at $tag"
echo
echo "Manual (UI-only): tick \"Publish this Action to the GitHub Marketplace\""
echo "on the release to refresh the listing:"
echo "  https://github.com/bertpl/gitsvg-action/releases/tag/$tag"
