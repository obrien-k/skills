#!/usr/bin/env bash
# verbiagating — Claude Code statusLine adapter.
#
# Renders an escalating "wait strip" as an extra status-line row while a turn is
# in flight. Tier is driven by elapsed-since-turn-start (stamped by the
# UserPromptSubmit hook, cleared by the Stop hook) and biased upward by context
# fill. Chains the user's prior statusLine command so it is never clobbered.
#
# Host-agnostic core (mirrors the renderStrip() spec in SKILL.md): select_tier()
# + render_strip() take only plain values, no Claude-specific imports. Everything
# above them is the Claude Code glue (JSON parse, state files, base passthrough).
set -uo pipefail

input=$(cat)

VG_HOME="${VG_HOME:-$HOME/.claude/verbiagating}"
CORPUS="$VG_HOME/corpus.tsv"
MODE_FILE="$VG_HOME/mode"                 # "plain" (default) | "osc8"
BASE_FILE="$VG_HOME/base-statusline.cmd"  # the user's prior statusLine command
STATE_DIR="${TMPDIR:-/tmp}/verbiagating"
CLOSEOUT_LINGER=600                       # holds the closeout until the next turn (turn-start clears it); capped so an abandoned session doesn't show it forever

# ---------------------------------------------------------------------------
# Host-agnostic core
# ---------------------------------------------------------------------------

# select_tier <elapsed_seconds> <context_pct> -> echoes: silent|light|medium|sweet|heavy
# Elapsed always wins when higher; context fill only lifts the floor.
select_tier() {
  local elapsed="$1" ctx="$2" rank=0
  [ "$elapsed" -lt 0 ] && { echo silent; return; }
  [ "$elapsed" -ge 30 ]  && rank=1
  [ "$elapsed" -ge 100 ] && rank=2
  [ "$elapsed" -ge 600 ] && rank=3
  # token-load bias: big context => long wait likely, open higher up the ladder
  if   [ "$ctx" -ge 75 ] && [ "$elapsed" -ge 30 ]; then [ "$rank" -lt 2 ] && rank=2
  elif [ "$ctx" -ge 50 ] && [ "$elapsed" -ge 60 ]; then [ "$rank" -lt 2 ] && rank=2
  fi
  # 60 min+ aliases straight to the loudest tier, no ramp
  [ "$elapsed" -ge 3600 ] && rank=3
  # 6-7 min sweet-spot versioned drop sits inside the medium band
  if [ "$elapsed" -ge 360 ] && [ "$elapsed" -lt 420 ]; then echo sweet; return; fi
  case "$rank" in 0) echo silent;; 1) echo light;; 2) echo medium;; 3) echo heavy;; esac
}

# fmt_dur <seconds> -> "Ns" under a minute, else "Mm Ss"
fmt_dur() {
  local s="$1"
  if [ "$s" -ge 60 ]; then printf '%dm %ds' "$((s/60))" "$((s%60))"; else printf '%ds' "$s"; fi
}

# render_strip <label> <url> <mode> -> echoes the strip string (no host styling)
render_strip() {
  local label="$1" url="$2" mode="$3"
  if [ -z "$url" ]; then printf '%s' "$label"; return; fi
  if [ "$mode" = "osc8" ]; then
    # BEL-terminated OSC 8 — clickable label, verified-OSC hosts only
    printf '\033]8;;%s\a%s\033]8;;\a ↗' "$url" "$label"
  else
    # static fallback, viable in any terminal
    printf '%s — %s' "$label" "$url"
  fi
}

# ---------------------------------------------------------------------------
# Claude Code glue
# ---------------------------------------------------------------------------

# 1. Base statusLine passthrough — never clobber the user's own line.
base_out=""
if [ -f "$BASE_FILE" ]; then
  base_cmd=$(cat "$BASE_FILE")
  [ -n "$base_cmd" ] && base_out=$(printf '%s' "$input" | eval "$base_cmd" 2>/dev/null)
fi

# 2. Session id + context fill from stdin.
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[ -z "$ctx_pct" ] && ctx_pct=0
# Total input-token count = context fill. Lands in the tens of thousands in any
# real session, so a 69,000–69,999 band is a reachable, version-proof peg for the
# "Nice." nod — unlike an exact output-token 69, dead on older clients and a
# one-in-a-million graze on newer ones.
in_tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
[ -z "$in_tokens" ] && in_tokens=0
NICE_LO=69000; NICE_HI=69999   # the "nice" band — retarget by moving these two

# 10万ボルト (v8) — the 💀 graveyard zone. 10万 = 100,000; once context fill crosses
# 100k input tokens you're "beyond ere," so it latches as a threshold (not a
# fleeting band like NICE). Token-addressed, no specific tier.
VOLT_TOKENS=100000
VOLT_LABEL='⚡ v8 — 10万ボルト'
VOLT_URL='https://www.youtube.com/watch?v=5QzEoWeybp4'

# Ken combo (KEN_*) — fired at the middling ~50% context mark (comme ci comme
# ça, the halfway slog), not a time band. Context-addressed, no specific tier.
# "hadouken" is the user-facing trigger (phrases.tsv); KEN_* is the internal name.
KEN_PCT=50
KEN_LABEL='👊Ken combo-ing.⚔️'
KEN_URL='https://ssb.wiki.gallery/images/8/87/Kencombo.gif'

# 3. Elapsed since turn start (UserPromptSubmit hook wrote the epoch).
elapsed=-1
start_val=0
start_file="$STATE_DIR/$session_id"
done_file="$STATE_DIR/$session_id.done"
pin_file="$STATE_DIR/$session_id.pin"   # phrase-pinned item for this turn (turn-start.sh)
last_file="$STATE_DIR/$session_id.last" # the item currently spinning, for the closeout to freeze on
if [ -n "$session_id" ] && [ -f "$start_file" ]; then
  start_val=$(cat "$start_file" 2>/dev/null || echo 0)
  [ -n "$start_val" ] && elapsed=$(( $(date +%s) - start_val ))
fi

# 4. Strip: an active-wait tier, or a brief post-turn closeout.
strip=""
mode="plain"; [ -f "$MODE_FILE" ] && mode=$(tr -d '[:space:]' < "$MODE_FILE")
if [ "$elapsed" -ge 0 ]; then
  # --- active wait. First PICK the item (precedence: phrase-pin > 69 > 10万ボルト
  #     (💀 ≥100k) > Ken (~50%) > tiered), then RENDER it with the spinning
  #     INDIGO→MAGENTA gradient and record it for the closeout to freeze on. ---
  picked_label=""; picked_url=""; bare=""

  # 1) Phrase-pin: turn-start.sh matched a key phrase and wrote "<label>\t<url>".
  if [ -n "$session_id" ] && [ -f "$pin_file" ]; then
    IFS=$'\t' read -r pin_label pin_url < "$pin_file" 2>/dev/null || true
    [ -n "${pin_label:-}" ] && { picked_label="$pin_label"; picked_url="${pin_url:-}"; }
  fi

  # 2) The 69: a subtle homie nod — bare label, never spun or linked.
  if [ -z "$picked_label" ] && [ "$in_tokens" -ge "$NICE_LO" ] && [ "$in_tokens" -le "$NICE_HI" ]; then
    bare="Nice."
  fi

  # 2b) 10万ボルト: the 💀 graveyard zone — context fill at/beyond 100k input tokens.
  if [ -z "$picked_label" ] && [ -z "$bare" ] && [ "$in_tokens" -ge "$VOLT_TOKENS" ]; then
    picked_label="$VOLT_LABEL"; picked_url="$VOLT_URL"
  fi

  # 3) Ken combo at the ~50% halfway mark.
  if [ -z "$picked_label" ] && [ -z "$bare" ] && [ "$ctx_pct" = "$KEN_PCT" ]; then
    picked_label="$KEN_LABEL"; picked_url="$KEN_URL"
  fi

  # 4) Normal tiered item, held stable for the whole turn.
  if [ -z "$picked_label" ] && [ -z "$bare" ]; then
    tier=$(select_tier "$elapsed" "$ctx_pct")
    if [ "$tier" != "silent" ] && [ -f "$CORPUS" ]; then
      labels=(); urls=()
      while IFS=$'\t' read -r t label url; do
        [ "$t" = "$tier" ] || continue
        labels+=("$label"); urls+=("$url")
      done < "$CORPUS"
      n=${#labels[@]}
      if [ "$n" -gt 0 ]; then
        # Deterministic pick keyed on session+tier+turn: stable across the turn's
        # refreshes (no flicker), fresh on the next turn. No extra state writes.
        h=$(printf '%s' "${session_id}:${tier}:${start_val}" | cksum | cut -d' ' -f1)
        idx=$(( h % n ))
        picked_label="${labels[$idx]}"; picked_url="${urls[$idx]}"
      fi
    fi
  fi

  if [ -n "$bare" ]; then
    strip="$bare"
  elif [ -n "$picked_label" ]; then
    # Spin the picked item (INDIGO→MAGENTA band, cycling on elapsed); fall back to
    # the plain label if node is unavailable. Record it for the closeout freeze.
    spun="$picked_label"
    if command -v node >/dev/null 2>&1 && [ -f "$VG_HOME/rainbow.js" ]; then
      s=$(node "$VG_HOME/rainbow.js" spin "$elapsed" "$picked_label" 2>/dev/null)
      [ -n "$s" ] && spun="$s"
    fi
    strip=$(render_strip "$spun" "$picked_url" "$mode")
    [ -n "$session_id" ] && printf '%s\t%s\n' "$picked_label" "${picked_url}" > "$last_file"
  fi
elif [ -n "$session_id" ] && [ -f "$done_file" ]; then
  # --- closeout: ".done" holds line 1 "<elapsed> <finished_epoch>" and line 2
  #     "<label>\t<url>" (the item that was spinning). Linger, then freeze it as a
  #     full rainbow ending on #c594a9. ---
  done_elapsed=0; done_epoch=0; done_label=""; done_url=""
  { read -r done_elapsed done_epoch; IFS=$'\t' read -r done_label done_url; } < "$done_file" 2>/dev/null || true
  : "${done_epoch:=0}"; : "${done_elapsed:=0}"
  if [ $(( $(date +%s) - done_epoch )) -lt "$CLOSEOUT_LINGER" ]; then
    if command -v node >/dev/null 2>&1 && [ -f "$VG_HOME/rainbow.js" ]; then
      # "done <dur> [label] [url]" → "<rainbow label> for <dur>\t<url>" (empty
      # label falls back to the default 10万ボルト drop). Carry it through render_strip.
      done_line=$(node "$VG_HOME/rainbow.js" done "$done_elapsed" "${done_label:-}" "${done_url:-}" 2>/dev/null)
      IFS=$'\t' read -r out_label out_url <<EOF
$done_line
EOF
      [ -n "${out_label:-}" ] && strip=$(render_strip "$out_label" "${out_url:-}" "$mode")
    fi
    [ -z "$strip" ] && strip="verbiagated for $(fmt_dur "$done_elapsed")"
  fi
fi

# 5. Emit base line(s), then the strip as its own row.
printf '%s' "$base_out"
[ -n "$strip" ] && printf '\n%s' "$strip" || true
