#!/usr/bin/env bash
#
# Mr. Robot — Sweep Context resolver 🧭
#
# Resolves the facts every later phase depends on, and the Ownership Gate
# verdict, in ONE place. Emits a shell-sourceable Sweep Context on stdout;
# all diagnostics go to stderr. STRICTLY READ-ONLY — git reads + `gh api` GETs
# only, never a mutation — so it is safe to run anytime (that read-only property
# is also how it is "tested" absent a test runner in this repo).
#
# Contract (stdout):
#   RC_MODE=proceed|local-only|hard-stop|needs-confirm
#   RC_REMOTE=<remote name, by name — never assumed "origin">
#   RC_HOST=<github.com|gitlab.com|…|"" when no remote>
#   RC_OWNER=<owner/org login>
#   RC_REPO=<repo name>
#   RC_DEFAULT=<default branch>
#
# Ownership Gate (fail-closed — anything not positively confirmed yours-and-
# pushable is NOT `proceed`):
#   no remote .................................... local-only
#   GitHub host + permissions.push == true ....... proceed
#   GitHub host + push false / empty / API error . hard-stop
#   non-GitHub host (gitlab, …) .................. needs-confirm  (agent picks glab / asks)
#
# Usage (from inside the target repo, or set MR_ROBOT_REPO=<repo-root>):
#   eval "$(scripts/resolve-context.sh)"      # then use $RC_REMOTE / $RC_DEFAULT / $RC_MODE
#   scripts/resolve-context.sh                # print the Sweep Context
#
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }   # diagnostics → stderr, never stdout

repo="${MR_ROBOT_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$repo" ] || { log "✗ not inside a git repo (cd in, or set MR_ROBOT_REPO)"; exit 1; }
git() { command git -C "$repo" "$@"; }

emit() {
  printf 'RC_MODE=%s\n'    "$1"
  printf 'RC_REMOTE=%s\n'  "$2"
  printf 'RC_HOST=%s\n'    "$3"
  printf 'RC_OWNER=%s\n'   "$4"
  printf 'RC_REPO=%s\n'    "$5"
  printf 'RC_DEFAULT=%s\n' "$6"
}

# Current branch is the fallback default everywhere below.
cur="$(git branch --show-current 2>/dev/null || echo '')"

# --- Resolve the remote BY NAME — never assume "origin". A gh-cloned repo or a
# fork uses other names (gh, upstream); a hardcoded `origin` check fails OPEN,
# misreading such a repo as "no remote" → LOCAL-ONLY → swept. ------------------
remote="$(git remote | grep -qx origin && echo origin || git remote | head -1)"
if [ -z "$remote" ]; then
  log "→ no remote: LOCAL-ONLY (the repo is yours by definition, nothing to push)"
  emit local-only "" "" "" "" "${cur:-HEAD}"
  exit 0
fi

url="$(git remote get-url "$remote" 2>/dev/null || true)"
host="$(printf '%s' "$url" | sed -E 's#^git@([^:]+):.*#\1#; s#^https?://([^/]+)/.*#\1#; s#^ssh://git@([^/:]+).*#\1#')"
owner="$(printf '%s' "$url" | sed -E 's#(git@[^:]+:|ssh://git@[^/]+/|https?://[^/]+/)##; s#/?\.git$##; s#/.*##')"
name="$(basename "$url" .git)"

# Default branch — remote HEAD, then API (GitHub only), then current branch.
default="$(git symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null | sed "s#$remote/##" || true)"

case "$host" in
  github.com)
    push="$(gh api "repos/$owner/$name" --jq '.permissions.push' 2>/dev/null || echo '')"
    [ -n "$default" ] || default="$(gh api "repos/$owner/$name" --jq '.default_branch' 2>/dev/null || echo '')"
    [ -n "$default" ] || default="$cur"
    if [ "$push" = "true" ]; then
      log "→ GitHub, push rights confirmed for $owner/$name: PROCEED"
      emit proceed "$remote" "$host" "$owner" "$name" "$default"
    else
      log "→ GitHub, no confirmed push rights for $owner/$name (push='$push'): HARD STOP"
      emit hard-stop "$remote" "$host" "$owner" "$name" "$default"
    fi
    ;;
  "")
    log "✗ could not parse host from remote URL '$url': HARD STOP (fail-closed)"
    emit hard-stop "$remote" "" "$owner" "$name" "${default:-$cur}"
    ;;
  *)
    [ -n "$default" ] || default="$cur"
    log "→ non-GitHub host ($host): NEEDS CONFIRM — use that forge's CLI (e.g. glab) or confirm ownership with the user"
    emit needs-confirm "$remote" "$host" "$owner" "$name" "$default"
    ;;
esac
