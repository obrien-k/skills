#!/usr/bin/env bash
# verbiagating — UserPromptSubmit hook. Stamps turn-start epoch so the
# statusLine adapter can measure how long the wait has run, and — if the prompt
# matches a key phrase in phrases.tsv — pins a specific corpus item for this
# turn's wait. Stays silent: UserPromptSubmit stdout is injected as context, so
# this must print nothing.
set -uo pipefail
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0
dir="${TMPDIR:-/tmp}/verbiagating"
mkdir -p "$dir"
rm -f "$dir/$sid.done"   # drop any lingering closeout from the previous turn
rm -f "$dir/$sid.pin"    # drop any stale phrase-pin from the previous turn
rm -f "$dir/$sid.last"   # drop the previous turn's spinning-item record
date +%s > "$dir/$sid"

# Phrase-pin: lowercase the prompt, pin the first phrases.tsv row whose phrase
# is a substring. Writes "<label>\t<url>" for statusline.sh to render.
VG_HOME="${VG_HOME:-$HOME/.claude/verbiagating}"
phrases="$VG_HOME/phrases.tsv"
if [ -f "$phrases" ]; then
  prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' | tr '[:upper:]' '[:lower:]')
  if [ -n "$prompt" ]; then
    while IFS=$'\t' read -r phrase label url; do
      case "$phrase" in ''|'#'*) continue;; esac
      [ -z "$label" ] && continue
      lc_phrase=$(printf '%s' "$phrase" | tr '[:upper:]' '[:lower:]')
      case "$prompt" in
        *"$lc_phrase"*) printf '%s\t%s\n' "$label" "$url" > "$dir/$sid.pin"; break;;
      esac
    done < "$phrases"
  fi
fi
exit 0
