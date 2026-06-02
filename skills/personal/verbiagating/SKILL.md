---
name: verbiagating
description: Fun/troll status strip above the user input during long model waits. Escalates from cute to chaotic based on elapsed time. Part of the claudx-pi TUI extension.
---

# Verbiagating ⭐

> *The model is thinking. You are waiting. Here's something.*

A status strip rendered above the text input whenever a response is taking a while. One item, held for the full wait. Escalates tier by elapsed time; token load at send time can bias the starting tier upward.

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

The strip is a Pi **above-editor widget** (`ctx.ui.custom((tui, theme, kb, done) => …)`
— the same slot `plan-mode` drives), **not** a markdown surface. There's no markdown
pass: `[text](url)` would print literally. The widget's `render` fn emits styled text
directly, so links are done at the terminal layer, not via markdown.

```
⭐ [label] ↗
> user input █
```

The `[label]` is pulled **directly** from the corpus item — the backtick-wrapped text
— and the label itself is the **clickable link** (the `↗` is the affordance; the raw
URL never shows). Wrap the label in an OSC 8 terminal hyperlink:

```
ESC ]8;;{url} ESC \  {label}  ESC ]8;;ESC \
\x1b]8;;{url}\x1b\\{label}\x1b]8;;\x1b\\
```

- Works in OSC 8-aware terminals (iTerm2, kitty, WezTerm, recent VTE). **Verify
  against Pi's actual render path before shipping** — some TUI renderers miscount
  display width on embedded escapes or strip them. If Pi does, fall back to printing
  the bare `{url}` after the label; most terminals ⌘-click-linkify a plain URL anyway.
- Never inject the skill's own name into a strip: **"verbiagating" (or any similar
  verbiage) must not appear in any strip message.** It's the internal name of the
  feature, nothing more.

## Corpus

### Light — 30–99 sec
- `💃Breakdancing🕺` → https://www.youtube.com/watch?v=Hr95rKEYT5E
- `💅Bump a bitch.. just kiddin🖕` — playwright vibes: click a button, nudge the mouse, tab through, check screen reader

### Medium — 1–10 min
- `⚡It's Pikachu!` → https://www.youtube.com/watch?v=5QzEoWeybp4
- `soh-ho-kay-her'rs-thee-earth'-szjhst-chillin 🌏🌎💥🌍 .!Damn!🌏🌎💥` → https://www.youtube.com/watch?v=nZMwKPmsbWE

### The Sweet Spot — 6–7 min
- `Conversion, softtware version 🥁 7.0` → https://www.youtube.com/watch?v=iywaBOMvYLI&list=RDiywaBOMvYLI&start_radio=1

### Heavy — 10 min+
- `We're no strangers to love..` → https://www.youtube.com/watch?v=eBGIQ7ZuuiU
- `🧌FUCKINDOITLIVE.gif👹` → https://www.youtube.com/watch?v=Qy-Y3HJNU_s

## Token Load Bias

At send time, snapshot `ctx.getContextUsage().tokens` and divide by the window
max to get a fill ratio. Big context = the wait is likely to be long, so open
higher up the ladder instead of starting cute:

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

## Pi Wiring

```ts
pi.on("before_provider_request", (event, ctx) => {
  const usage = ctx.getContextUsage();
  // snapshot tokens → store for tier bias
});
```

- `estimateContextTokens(messages[])` as fallback if `getContextUsage()` returns null post-compaction
- Corpus lives in `.pi/skills/verbiagating.md` (skill file with YAML frontmatter `items[]`)
- One item picked per send; dismissed on response

## Open / TBD

- [x] What does "verbiagating" mean as a concept — **internal name only**; never shown in a strip. Labels come from the corpus backtick text + arrow + URL.
- [x] Breakdancing GIF URL
- [x] FUCKINDOITLIVE.gif URL
- [x] Large-context token threshold for tier-bias — fill-ratio table above; 60 min+ aliases to highest tier
- [x] More corpus items (user retrieving from /btw notes) — none found, moving on
