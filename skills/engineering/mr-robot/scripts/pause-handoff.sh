#!/usr/bin/env bash
#
# Mr. Robot — pause/handoff guard 📌
#
# Persists a handoff/resume doc so it survives a reboot but NEVER enters commit
# history. Enforces the Phase 2 local-only-files rule:
#   (a) refuses temp dirs (/tmp, $TMPDIR — macOS wipes them on boot)
#   (b) relocates the doc INTO the repo as a dotfile (.handoff-<topic>.md)
#   (c) appends the per-clone .git/info/exclude entry, then VERIFIES git neither
#       tracks nor surfaces the file before reporting "paused safe".
#
# Usage (run from inside the target repo, or set MR_ROBOT_REPO=<repo-root>):
#   pause-handoff.sh <topic> [source-file]   # relocate an existing draft (often /tmp)
#   some-generator | pause-handoff.sh <topic> # read the body from stdin
#   pause-handoff.sh <topic>                  # create/keep an empty stub
#
set -euo pipefail

topic="${1:?usage: pause-handoff.sh <topic> [source-file]}"
src="${2:-}"

# Resolve the repo root — never assume cwd is it.
repo="${MR_ROBOT_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[ -n "$repo" ] || { echo "✗ not inside a git repo (cd in, or set MR_ROBOT_REPO)"; exit 1; }

# Slugify the topic.
slug="$(printf '%s' "$topic" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-_')"
[ -n "$slug" ] || { echo "✗ topic '$topic' produced an empty slug"; exit 1; }
name=".handoff-$slug.md"
dest="$repo/$name"

# (a) Refuse to persist under a temp dir — that's the whole point. Resolve the
# *physical* path (macOS symlinks /var → /private/var, and $TMPDIR lives under
# /var/folders), so the prefix match can't be dodged by a symlink.
phys_dest="$(cd "$repo" && pwd -P)/$name"
tmp_real="$(cd "${TMPDIR:-/dev/null/never}" 2>/dev/null && pwd -P || echo /dev/null/never)"
case "$phys_dest" in
  /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*|"$tmp_real"/*)
    echo "✗ refusing: repo lives under a temp dir, the handoff would not survive a reboot ($phys_dest)"; exit 1 ;;
esac

# (b) Relocate / write the handoff into the repo as a dotfile.
if [ -n "$src" ]; then
  [ -f "$src" ] || { echo "✗ source not found: $src"; exit 1; }
  mv -f "$src" "$dest"; echo "→ relocated $src → $name"
elif [ ! -t 0 ]; then
  cat > "$dest"; echo "→ wrote handoff from stdin → $name"
else
  [ -f "$dest" ] || printf '# Handoff — %s\n\n_(fill me in)_\n' "$topic" > "$dest"
  echo "→ handoff ready at $name"
fi

# (c) Exclude via the per-clone .git/info/exclude (idempotent).
gitdir="$(git -C "$repo" rev-parse --git-dir)"
case "$gitdir" in /*) ;; *) gitdir="$repo/$gitdir" ;; esac   # normalize to absolute
exclude="$gitdir/info/exclude"
mkdir -p "$(dirname "$exclude")"
if ! grep -qxF "$name" "$exclude" 2>/dev/null; then
  printf '\n# local-only resume handoff (never commit)\n%s\n' "$name" >> "$exclude"
  echo "→ excluded via ${exclude#"$repo"/}"
fi

# Verify: never already tracked, and git status must not surface it.
if git -C "$repo" ls-files --error-unmatch "$name" >/dev/null 2>&1; then
  echo "✗ $name is already TRACKED — purge it first: git rm --cached $name"; exit 1
fi
if [ -n "$(git -C "$repo" status --short --untracked-files=all -- "$name" 2>/dev/null)" ]; then
  echo "✗ git status still lists $name — exclude not effective, NOT safe"; exit 1
fi

echo "✓ paused safe — $name persists across reboot, invisible to git"
