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
CLOSEOUT_LINGER=6                         # seconds the "verbiagated for X" line holds post-turn

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
# Live output-token count of the most recent response. Small enough to land on
# exactly 69 now and then — the peg for the "Nice." nod (NICE_TOKENS below).
out_tokens=$(printf '%s' "$input" | jq -r '.context_window.total_output_tokens // 0')
[ -z "$out_tokens" ] && out_tokens=0
NICE_TOKENS=69   # retarget by changing this one number

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
if [ -n "$session_id" ] && [ -f "$start_file" ]; then
  start_val=$(cat "$start_file" 2>/dev/null || echo 0)
  [ -n "$start_val" ] && elapsed=$(( $(date +%s) - start_val ))
fi

# 4. Strip: an active-wait tier, or a brief post-turn closeout.
strip=""
mode="plain"; [ -f "$MODE_FILE" ] && mode=$(tr -d '[:space:]' < "$MODE_FILE")
if [ "$elapsed" -ge 0 ]; then
  # --- active wait. Overrides pierce the silent floor and win over the tiered
  #     pick; precedence: phrase-pin > 69 > Ken (~50%) > tiered item. ---

  # 1) Phrase-pin: turn-start.sh matched a key phrase and wrote "<label>\t<url>".
  if [ -n "$session_id" ] && [ -f "$pin_file" ]; then
    IFS=$'\t' read -r pin_label pin_url < "$pin_file" 2>/dev/null || true
    [ -n "${pin_label:-}" ] && strip=$(render_strip "$pin_label" "${pin_url:-}" "$mode")
  fi

  # 2) The 69: bare label, no url, no other context. A subtle homie nod.
  if [ -z "$strip" ] && [ "$out_tokens" = "$NICE_TOKENS" ]; then
    strip="Nice."
  fi

  # 3) Ken combo at the ~50% halfway mark.
  if [ -z "$strip" ] && [ "$ctx_pct" = "$KEN_PCT" ]; then
    strip=$(render_strip "$KEN_LABEL" "$KEN_URL" "$mode")
  fi

  # 4) Normal tiered item, held stable for the whole turn.
  if [ -z "$strip" ]; then
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
        strip=$(render_strip "${labels[$idx]}" "${urls[$idx]}" "$mode")
      fi
    fi
  fi
elif [ -n "$session_id" ] && [ -f "$done_file" ]; then
  # --- closeout: Stop hook recorded "<elapsed> <finished_epoch>"; linger briefly ---
  read -r done_elapsed done_epoch < "$done_file" 2>/dev/null || true
  : "${done_epoch:=0}"; : "${done_elapsed:=0}"
  if [ $(( $(date +%s) - done_epoch )) -lt "$CLOSEOUT_LINGER" ]; then
    strip="verbiagated for $(fmt_dur "$done_elapsed")"
  fi
fi

# 5. Emit base line(s), then the strip as its own row.
printf '%s' "$base_out"
[ -n "$strip" ] && printf '\n%s' "$strip" || true
