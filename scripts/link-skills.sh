#!/usr/bin/env bash
set -euo pipefail

# Links all skills in the repository to ~/.claude/skills, so that
# they can be used by the local Claude CLI.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.claude/skills"

# If ~/.claude/skills is a symlink that resolves into this repo, we'd end up
# writing the per-skill symlinks back into the repo's own skills/ tree. Detect
# and bail out instead of polluting the working copy.
if [ -L "$DEST" ]; then
  resolved="$(readlink -f "$DEST")"
  case "$resolved" in
    "$REPO"|"$REPO"/*)
      echo "error: $DEST is a symlink into this repo ($resolved)." >&2
      echo "Remove it (rm \"$DEST\") and re-run; the script will recreate it as a real dir." >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$DEST"

# Prune stale links: a symlink in DEST that points into this repo's skills/ tree
# but no longer resolves (its source skill was renamed, moved, or deleted). We
# only touch broken links that target THIS repo, so symlinks the user added by
# hand (or from other repos) are left alone.
for link in "$DEST"/*; do
  [ -L "$link" ] || continue
  [ -e "$link" ] && continue            # still resolves — keep
  raw_target="$(readlink "$link")"
  case "$raw_target" in
    "$REPO"/*)
      rm -f "$link"
      echo "pruned $(basename "$link") -> $raw_target (dangling)"
      ;;
  esac
done

find "$REPO/skills" -name SKILL.md -not -path '*/node_modules/*' -not -path '*/deprecated/*' -print0 |
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  name="$(basename "$src")"
  target="$DEST/$name"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi

  ln -sfn "$src" "$target"
  echo "linked $name -> $src"
done
