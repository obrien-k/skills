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
start_file="$dir/$sid"
if [ -f "$start_file" ]; then
  start=$(cat "$start_file" 2>/dev/null || echo 0)
  now=$(date +%s)
  elapsed=$(( now - start ))
  if [ "$elapsed" -ge 30 ]; then
    # ".done": line 1 "<elapsed> <epoch>", line 2 "<label>\t<url>" — the item that
    # was spinning, snapshotted so the closeout freezes on it. Prefer .last (what
    # actually spun); if no refresh ever captured it, fall back to the phrase-pin so
    # an explicit pin still survives. With neither, line 2 is empty and the closeout
    # reconstructs the tiered pick deterministically (see statusline.sh).
    {
      printf '%s %s\n' "$elapsed" "$now"
      if [ -f "$dir/$sid.last" ]; then
        cat "$dir/$sid.last"
      elif [ -f "$dir/$sid.pin" ]; then
        cat "$dir/$sid.pin"
      fi
    } > "$dir/$sid.done"
  fi
  rm -f "$start_file"
fi
rm -f "$dir/$sid.last" "$dir/$sid.pin"   # spinning-item record + phrase-pin are per-turn
exit 0
