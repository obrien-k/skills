#!/usr/bin/env bash
# verbiagating — Stop hook. Records the turn's elapsed time as a closeout marker
# ("<elapsed> <finished_epoch>") that the statusLine lingers briefly as
# "verbiagated for Xm Ys", then clears the active turn stamp so the wait strip
# dismisses. Only marks waits past the silent floor (>=30s); shorter turns just
# clear. Silent on stdout.
set -uo pipefail
input=$(cat)
sid=$(printf '%s' "$input" | jq -r '.session_id // empty')
[ -z "$sid" ] && exit 0
dir="${TMPDIR:-/tmp}/verbiagating"
rm -f "$dir/$sid.pin"   # phrase-pin is per-turn; clear it once the wait ends
start_file="$dir/$sid"
if [ -f "$start_file" ]; then
  start=$(cat "$start_file" 2>/dev/null || echo 0)
  now=$(date +%s)
  elapsed=$(( now - start ))
  [ "$elapsed" -ge 30 ] && printf '%s %s\n' "$elapsed" "$now" > "$dir/$sid.done"
  rm -f "$start_file"
fi
exit 0
