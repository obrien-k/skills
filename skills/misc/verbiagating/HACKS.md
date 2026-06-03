# Verbiagating — Hacks (divergence sandbox)

**This is a sandbox, not the runtime.** The shipping adapter is `scripts/` + the spec in
[SKILL.md](SKILL.md); those stay canonical. This file preserves a *fixed reference build*
produced in a side session — improvements that never made it into `scripts/` — so they're
something to fork from **with intent**, not lost to a transcript. Nothing here is installed
or referenced by the runtime; copy a block out when you want it.

Base is the current shipping `scripts/` (so it keeps upstream's `|| true` exit fix), with the
session fixes layered on top.

## Divergences from shipping `scripts/` (HEAD)

- **`statusline.sh`**
  - `[ -z "$base_out" ] && base_out=42` — placeholder when no base statusLine is configured,
    so the strip never renders as a stray second row beneath a blank first line.
  - "Nice." peg moved from exact `total_output_tokens == 69` to `total_input_tokens` in the
    **69,000–69,999** band (`NICE_LO`/`NICE_HI`). Version-proof: `total_output_tokens` only
    became per-response in Claude Code v2.1.132 (cumulative before), so the exact peg was
    dead on older clients and a one-in-a-million graze on newer ones; a 69k *output* band
    would overshoot most models' max-output cap. Input tokens trip once as context crosses 69k.
  - `KEN_*` comments + the precedence comment de-HADOUKEN'd to "Ken (~50%)";
    `KEN_URL` points at the direct GIF (`ssb.wiki.gallery/.../Kencombo.gif`) instead
    of the shipping wiki-page link.
  - Keeps upstream's trailing `|| true`.
- **`turn-start.sh`** — stale-marker GC (`find … -mtime +1 -delete`) so dead sessions don't
  litter `$TMPDIR/verbiagating`.
- **`gallery.sh`** — a tier-preview renderer; not present in `scripts/` at all.
- **`phrases.tsv`** — the `hadouken` pin links the Ken combo GIF
  (`ssb.wiki.gallery/.../Kencombo.gif`), matching `KEN_URL`. "hadouken" is the
  user-facing trigger; `KEN_*` is the internal name.

> The *Simulacra / generic-agent profile* — a paste-in prompt payload that mimics the strip in
> a runtime-less agent (ChatGPT/Custom GPT), keyed on the agent's own answer length — now lives
> in [SIMULACRA.md](SIMULACRA.md). (It shares the Ken-combo GIF used by `KEN_URL` above.)

---

## `statusline.sh`

```bash
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
# No base statusLine configured? Hold a placeholder so the strip never renders as a
# stray second row beneath a blank first line. (42, for now.)
[ -z "$base_out" ] && base_out=42

# 2. Session id + context fill from stdin.
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
[ -z "$ctx_pct" ] && ctx_pct=0
# Total input tokens in the live context (input + cache reads). Sits in the tens
# of thousands in any real session, so a 69,xxx band is a reachable, version-proof
# peg for the "Nice." nod — unlike an exact output-token 69, which was dead on
# pre-v2.1.132 clients (cumulative) and a one-in-a-million graze on newer ones.
in_tokens=$(printf '%s' "$input" | jq -r '.context_window.total_input_tokens // 0')
[ -z "$in_tokens" ] && in_tokens=0
NICE_LO=69000; NICE_HI=69999   # the "nice" band — retarget by moving these two

# Ken's combo (KEN_*) — fired at the middling ~50% context mark (comme ci comme
# ça, the halfway slog), not a time band. Context-addressed, no specific tier.
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
  if [ -z "$strip" ] && [ "$in_tokens" -ge "$NICE_LO" ] && [ "$in_tokens" -le "$NICE_HI" ]; then
    strip="Nice."
  fi

  # 3) Ken's combo at the ~50% halfway mark.
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
```

## `turn-start.sh`

```bash
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
find "$dir" -type f -mtime +1 -delete 2>/dev/null || true   # GC dead sessions' stale markers
rm -f "$dir/$sid.done"   # drop any lingering closeout from the previous turn
rm -f "$dir/$sid.pin"    # drop any stale phrase-pin from the previous turn
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
```

## `turn-end.sh`

```bash
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
```

## `corpus.tsv`

```tsv
light	💃Breakdancing🕺	https://www.youtube.com/watch?v=Hr95rKEYT5E
light	💅Bump a bitch.. just kiddin🖕	
light	🎉🤖 Elliot shipped — v1.0!	
medium	⚡It's Pikachu!	https://www.youtube.com/watch?v=5QzEoWeybp4
medium	soh-ho-kay-her'rs-thee-earth'-szjhst-chillin 🌏🌎💥🌍 .!Damn!🌏🌎💥	https://www.youtube.com/watch?v=nZMwKPmsbWE
sweet	Conversion, software version 🥁 7.0	https://www.youtube.com/watch?v=iywaBOMvYLI&list=RDiywaBOMvYLI&start_radio=1
heavy	We're no strangers to love..	https://www.youtube.com/watch?v=eBGIQ7ZuuiU
heavy	🧌FUCKINDOITLIVE.gif👹	https://www.youtube.com/watch?v=Qy-Y3HJNU_s
```

## `phrases.tsv`

```tsv
# verbiagating — phrase-pin map.  phrase<TAB>label<TAB>url
# turn-start.sh lowercases your prompt and pins the FIRST row whose <phrase>
# appears as a substring. The pinned <label>/<url> then overrides the tiered
# item for that turn's wait (precedence: pin > 69 > Ken > tier). url optional.
# Lines starting with # and blank lines are ignored.
# Pick DISTINCTIVE trigger words — a common one (fix, build, test) would pin on
# nearly every prompt. Edit freely.
#
hadouken	🔥🌀 HADOUKEN	https://ssb.wiki.gallery/images/8/87/Kencombo.gif
shoryuken	🐉☝️ SHORYUKEN
rickroll	🎵 Never gonna give you up	https://www.youtube.com/watch?v=eBGIQ7ZuuiU
ship it	🎉🤖 Elliot shipped — v1.0!
yolo	🎲 no take-backs
```

## `gallery.sh`

```bash
#!/usr/bin/env bash
# verbiagating — preview gallery. Renders one simulacra card per tier so you can
# eyeball the plain-text format without pasting the payload into a GPT. Pure
# decoration, no runtime: it just prints the cards the Simulacra Profile describes.
# Optional arg renders a single tier: light|medium|sweet|heavy|69|pin
set -uo pipefail

WIDTH=12   # bar cells

bar() { # bar <pct> -> "[████░░░░░░░░] NN%"
  local pct="$1" filled i out=""
  filled=$(( pct * WIDTH / 100 ))
  for ((i=0; i<WIDTH; i++)); do
    if [ "$i" -lt "$filled" ]; then out+="█"; else out+="░"; fi
  done
  printf '[%s] %d%%' "$out" "$pct"
}

card() { # card <pct> <label> <url> <body...>
  local pct="$1" label="$2" url="$3"; shift 3
  bar "$pct"; printf '\n%s\n' "$label"
  [ -n "$url" ] && printf '%s\n' "$url"
  if [ "$#" -gt 0 ]; then printf '\n'; printf '%s\n' "$@"; fi
}

render() {
  case "$1" in
    light)
      card 35 "💃 Breakdancing 🕺" "https://www.youtube.com/watch?v=Hr95rKEYT5E" ;;
    medium)
      card 75 "⚡ It's Pikachu!" "https://www.youtube.com/watch?v=5QzEoWeybp4" \
        "status:" \
        "  tail wagging............. OK" \
        "  brain cell............... 1/1" \
        "  vibes.................... MAXIMUM" ;;
    sweet)
      card 88 "Conversion, software version 🥁 7.0" \
        "https://www.youtube.com/watch?v=iywaBOMvYLI" ;;
    heavy)
      card 100 "🧌 FUCKINDOITLIVE.gif 👹" "https://www.youtube.com/watch?v=Qy-Y3HJNU_s" \
        "mission report:" \
        "  ✓ observed the universe" \
        "  ✓ learned nothing" \
        "  ✓ had a great time" ;;
    69)
      printf 'Nice.\n' ;;            # the 69 override: bare, no bar, no body, no closeout
    pin)
      card 75 "🔥🌀 HADOUKEN" "https://ssb.wiki.gallery/images/8/87/Kencombo.gif" ;;
    *) printf 'unknown tier: %s\n' "$1" >&2; return 1 ;;
  esac
}

if [ "$#" -ge 1 ]; then
  render "$1"
  exit
fi

# Full gallery: every tier, a rule between cards, then the one closeout line.
tiers=(light medium sweet heavy pin)
for t in "${tiers[@]}"; do
  printf '── %s ──\n\n' "$t"
  render "$t"
  printf '\n'
done
printf '── 69 (override) ──\n\n'; render 69; printf '\n'
printf 'verbiagated for 0m 23s. 🌸\n'
```
