---
name: verbiagating
description: Fun/troll status strip above the user input during long model waits. Escalates from cute to chaotic based on elapsed time. Part of the claudx-pi TUI extension.
---

# Verbiagating ⭐

> *The model is thinking. You are waiting. Here's something.*

A status strip rendered above the text input whenever a response is taking a while. One item, held for the full wait. Escalates tier by elapsed time; token load at send time can bias the starting tier upward.

> **Note:** this is pure **window-decoration** — a fun bit of chrome to watch while you wait. It changes nothing about the request, the model, or the result; pull it and the agent behaves identically.

## Timing Tiers

| Elapsed    | Tier        | Vibe                        |
|------------|-------------|-----------------------------|
| < 30 sec   | silent      | nothing shown               |
| 30–99 sec  | light       | cute, harmless              |
| 1–10 min   | medium      | playful chaos               |
| 6–7 min    | sweet spot  | versioned drop (see below)  |
| 10 min+    | heavy       | full troll, no apologies    |
| 60 min+    | heavy (max) | aliased straight to highest |

## Strip Format

The strip renders on Pi's **footer status line** via `ctx.ui.setStatus(key, text)` — a
plain styled string keyed by the extension, **not** a markdown surface. There's no
markdown pass: `[text](url)` would print literally. Styling is done with theme escapes
(`theme.fg("accent", …)`, `theme.fg("dim", …)`), so links are emitted at the terminal
layer, not via markdown.

```
[label] ↗
> user input █
```

The `[label]` is pulled **directly** from the corpus item — the backtick-wrapped text
— and the label itself is the **clickable link** (the `↗` is the affordance; the raw
URL never shows). Wrap the label in an OSC 8 terminal hyperlink, using the **BEL
(`\x07`) terminator** to match Pi's own convention:

```
\x1b]8;;{url}\x07{label}\x1b]8;;\x07
```

**Verified against Pi's render path** (`pi-coding-agent` 0.78 + bundled `pi-tui`):
- The footer only runs `sanitizeStatusText` (collapses `\r\n\t`) before `truncateToWidth`
  — it does **not** `stripAnsi` the rendered text, so the OSC 8 escapes survive.
- `pi-tui`'s `visibleWidth` strips OSC sequences before counting, so the URL bytes are
  **zero-width** — no layout/alignment breakage.
- `truncateToWidth` is hyperlink-aware (closes and re-opens an active OSC 8 link across a
  cut), so a long URL can't get shredded mid-sequence.
- Pi itself ships OSC 8 in its login dialog with the same BEL form. Current terminal
  (iTerm2 3.6.8) supports it.
- **Still keep the bare-`{url}` fallback** for OSC 8-blind terminals — most ⌘-click-linkify
  a plain URL anyway. Antigravity / other host TUIs remain untested; the fallback covers them.
- Never inject the skill's own name into a **wait** strip: **"verbiagating" (or any
  similar verbiage) must not appear in any tiered wait message.** It's the internal name
  of the feature, nothing more. **One sanctioned exception:** the post-turn *closeout*
  line is exactly `verbiagated for <Mm Ss>` — the name's only permitted appearance.

## Portable Rendering

The renderer must stay **host-agnostic** so the strip is at least *statically viable*
in another TUI or skill — not every host has Pi's OSC-aware width/truncation, and a
host that miscounts an embedded escape can break its own layout. So:

- **`plain` is the default, universal mode** — escape-free `{label} — {url}`. Safe in
  any TUI, any skill, any terminal; nothing to detect, nothing to strip. This is the
  "statically viable" floor.
- **`osc8` is opt-in**, enabled only on a host verified OSC-aware (Pi ✓, iTerm2 ✓). The
  choice is **static** — a config flag or one-time capability check, never per-render
  guessing.

The renderer is a pure function with **no host imports** (no Pi `ctx`/`theme`); the only
glue a host supplies is a one-line string sink (Pi: `setStatus`; another TUI: its
status/footer API; a plain skill: print a line):

```ts
type Item = { label: string; url?: string };
type LinkMode = "plain" | "osc8";

// BEL-terminated OSC 8 — widest terminal support.
const osc8 = (url: string, label: string) => `\x1b]8;;${url}\x07${label}\x1b]8;;\x07`;

export function renderStrip(item: Item, mode: LinkMode = "plain"): string {
  if (!item.url) return item.label;
  return mode === "osc8"
    ? `${osc8(item.url, item.label)} ↗`   // clickable label, verified hosts only
    : `${item.label} — ${item.url}`;        // static fallback, viable anywhere
}
```

Styling (Pi's `theme.fg(...)`) is layered by the host *around* this output, never baked
into it — that keeps the core string portable.

## Corpus

### Light — 30–99 sec
- `💃Breakdancing🕺` → https://www.youtube.com/watch?v=Hr95rKEYT5E
- `💅Bump a bitch.. just kiddin🖕` — playwright vibes: click a button, nudge the mouse, tab through, check screen reader
- `🎉🤖 Elliot shipped — v1.0!` — cameo: Mr. Robot just graduated to `engineering/`. He doesn't know what the fuss is about.

### Medium — 1–10 min
- `⚡It's Pikachu!` → https://www.youtube.com/watch?v=5QzEoWeybp4
- `soh-ho-kay-her'rs-thee-earth'-szjhst-chillin 🌏🌎💥🌍 .!Damn!🌏🌎💥` → https://www.youtube.com/watch?v=nZMwKPmsbWE

### The Sweet Spot — 6–7 min
- `Conversion, software version 🥁 7.0` → https://www.youtube.com/watch?v=iywaBOMvYLI&list=RDiywaBOMvYLI&start_radio=1

### Heavy — 10 min+
- `We're no strangers to love..` → https://www.youtube.com/watch?v=eBGIQ7ZuuiU
- `🧌FUCKINDOITLIVE.gif👹` → https://www.youtube.com/watch?v=Qy-Y3HJNU_s

## Token Load Bias

At send time, read `ctx.getContextUsage().percent` (the same fill ratio the footer
shows). Big context = the wait is likely to be long, so open higher up the ladder
instead of starting cute:

| Context fill        | Starting tier at first non-silent mark |
|---------------------|----------------------------------------|
| < 50% (~100k/200k)  | light (normal escalation)              |
| 50–75% (~100–150k)  | skip light → open at medium at 1 min   |
| > 75% (~150k+)      | open at medium at the 30s mark         |

Elapsed time always wins over token bias when it's the higher tier — bias only
lifts the *floor*, it never caps the ceiling.

**Hour+ alias to highest temps.** The 6–7 min "Sweet Spot" gives the scaffolding:
tiers can carry a version alias (the `7.0` drop). Extend that — any wait that
crosses **60 min** is aliased straight to the highest tier (heavy/max), regardless
of token fill. Long-haul waits get the loudest drop, no ramp.

## Overrides

Three signals can pre-empt the tier-selected item during an active wait. All
**pierce the silent floor** (they can show before the 30s mark), and precedence
runs **phrase-pin > 69 > Ken (~50%) > tiered item**.

### Phrase-pin (`phrases.tsv`)

Key phrases in the *prompt* pin a specific drop for that one turn — the
runtime-level analogue of the token-load bias, but content-addressed instead of
time-addressed. `turn-start.sh` lowercases the prompt and pins the first
`phrases.tsv` row whose `phrase` is a substring, writing `<label>\t<url>` to
`$TMPDIR/verbiagating/<sid>.pin`; `statusline.sh` renders it over the tier pick
for the whole wait; `turn-end.sh` clears it (per-turn). Data shape mirrors
`corpus.tsv` — `phrase⇥label⇥url`, `url` optional, `#`/blank lines ignored:

```
hadouken	🔥🌀 HADOUKEN	https://ssb.wiki.gallery/images/8/87/Kencombo.gif
```

This is also the answer to "why invoke `/verbiagating` each session?" — you
don't. The runtime is the three always-on hooks; the slash command only loads
this doc. Phrase-pins are how a *phrase* (not a manual invocation) tunes the
strip's level.

### The 69

When `context_window.total_output_tokens` of the most recent response lands on
exactly `69` (the `NICE_TOKENS` constant in `statusline.sh`), the strip shows a
bare `Nice.` — no url, no other context. `total_output_tokens` is the peg
because short replies occasionally hit 69 for real, so it fires as a rare
coincidence rather than never. Retarget by changing the one constant.

### Ken combo (`KEN_*`)

At the middling **~50% context** mark (`KEN_PCT`, the comme-ci-comme-ça halfway
slog) the strip shows `👊Ken combo-ing.⚔️` linked to the Ken Combo gif.
Context-addressed, not a time tier — it replaced the original 120–150s time-band
idea. The user can also invoke it by mentioning **hadouken** (the phrase-pin, which
links the same gif); internally it's `KEN_*`. Label/url/mark are the `KEN_LABEL` /
`KEN_URL` / `KEN_PCT` constants in `statusline.sh`.

## Pi Wiring

```ts
pi.on("before_provider_request", (_event, ctx) => {
  clearTimers();
  ctx.ui.setStatus(STATUS_KEY, "");           // clear stale strip
  const highContext = (ctx.getContextUsage()?.percent ?? 0) > 50;
  // schedule tier timers (light/medium/heavy), biased by highContext
});

pi.on("turn_end", (_event, ctx) => {
  clearTimers();
  ctx.ui.setStatus(STATUS_KEY, "");           // dismiss on response
});
```

- Each tier timer fires `ctx.ui.setStatus(STATUS_KEY, renderItem(pick(CORPUS[tier]), ctx))`.
- `getContextUsage()` can be null post-compaction — guard with `?? 0`.
- Corpus lives inline in the extension (`index.ts` `CORPUS` record); one item picked per tier, held until the next tier fires or `turn_end` clears it.

## Claude Code Adapter

A working host adapter ships in [`scripts/`](scripts/), driven entirely by Claude Code's
documented [statusLine](https://code.claude.com/docs/en/statusline) + hooks surface — no
forked client. The strip renders as a **second status-line row**; the user's own statusLine
is preserved and chained, never clobbered.

| Pi event | Claude Code mechanism | Role |
|---|---|---|
| `before_provider_request` | `UserPromptSubmit` hook (`turn-start.sh`) | stamp turn-start epoch under `$TMPDIR/verbiagating/<session_id>` |
| tier timers + `setStatus` | `statusLine` cmd (`statusline.sh`), `refreshInterval: 2` | re-runs every 2 s, reads elapsed + context %, renders the strip row |
| `turn_end` | `Stop` hook (`turn-end.sh`) | delete the stamp → strip dismisses on next refresh |

**Why `refreshInterval`.** Event-driven statusLine updates go quiet during the pre-token
wait; `refreshInterval` (min 1 s) re-runs the command on a fixed timer regardless, which is
what lets the tier escalate *while you wait* rather than only after the response lands.

**Signals come free in the statusLine stdin JSON** — no transcript parsing:
- `context_window.used_percentage` → the token-load bias table directly.
- `effort.level` (`low…max`) and `thinking.enabled` are available as extra difficulty
  signals if the bias logic is ever extended.
- `session_id` keys the per-session state file (stable across refreshes, unique per session
  — the docs' recommended key; never `$$`).

**Scripts** (`scripts/`, also the install payload):
- `corpus.tsv` — `tier⇥label⇥url` data, the one file to edit to change messages.
- `statusline.sh` — host-agnostic core (`select_tier`, `render_strip` — a faithful bash
  port of the TS `renderStrip` above) plus the Claude glue (JSON parse, state, base chain).
  Pick is `cksum(session:tier:turn_start) % n` — stable within a turn, fresh next turn, zero
  extra writes from the hot path.
- `turn-start.sh` / `turn-end.sh` — the two hooks. Both silent (UserPromptSubmit stdout is
  injected as context, so it must print nothing).

**Install** (global, `~/.claude`):
1. Copy `scripts/*` → `~/.claude/verbiagating/`, `chmod +x *.sh`.
2. Save the current `statusLine.command` verbatim → `~/.claude/verbiagating/base-statusline.cmd`
   (the wrapper `eval`s it and re-feeds stdin, so the existing line keeps working).
3. `jq`-merge into `~/.claude/settings.json`: point `statusLine.command` at
   `statusline.sh`, set `statusLine.refreshInterval: 2`, append the `UserPromptSubmit` and
   `Stop` hooks. Back up settings first; never overwrite sibling keys.
4. Mode: write `plain` (default) or `osc8` to `~/.claude/verbiagating/mode`.
5. **Restart Claude Code** — hook changes don't apply mid-session, and the statusLine
   command needs a workspace-trust accept on first run.

**Uninstall.** Restore `statusLine.command` from `base-statusline.cmd`, drop the
`refreshInterval` and the two hook entries, `rm -rf ~/.claude/verbiagating`. A
`settings.json.bak.verbiagating` backup is written at install time.

**Cost note.** `refreshInterval: 2` re-runs the *whole* chained statusLine (incl. the base's
git calls) every 2 s even when idle — Claude Code can't refresh one row in isolation. Bump
the interval or cache the base if that matters.
