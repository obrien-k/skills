---
name: verbiagating
description: Fun/troll status strip above the user input during long model waits. Escalates from cute to chaotic based on elapsed time. Part of the claudx-pi TUI extension.
---

# Verbiagating ⭐

> *The model is thinking. You are waiting. Here's something.*

A status strip rendered above the text input whenever a response is taking a while. One item, held for the full wait. Escalates tier by elapsed time; token load at send time can bias the starting tier upward.

## Timing Tiers

| Elapsed    | Tier     | Vibe                        |
|------------|----------|-----------------------------|
| < 30 sec   | silent   | nothing shown               |
| 30–99 sec  | light    | cute, harmless              |
| 1–10 min   | medium   | playful chaos               |
| 10 min+    | heavy    | full troll, no apologies    |

## Strip Format

```
⭐ [label]  [url]
> user input █
```

## Corpus

### Light — 30–99 sec
- `💃Breakdancing🕺` → [*(URL TBD)*](https://www.youtube.com/watch?v=Hr95rKEYT5E)
- `💅Bump a bitch.. just kiddin🖕` — playwright vibes: click a button, nudge the mouse, tab through, check screen reader

### Medium — 1–10 min
- `⚡It's Pikachu!` → https://www.youtube.com/watch?v=5QzEoWeybp4
- `soh-ho-kay-her'rs-thee-earth'-szjhst-chillin 🌏🌎💥🌍 .!Damn!🌏🌎💥` → https://www.youtube.com/watch?v=nZMwKPmsbWE

### The Sweet Spot - 6 - 7 min
- `Conversion, softtware version 🥁 \n
  7.0` → https://www.youtube.com/watch?v=iywaBOMvYLI&list=RDiywaBOMvYLI&start_radio=1

### Heavy — 10 min+
- `We're no strangers to love..` → https://www.youtube.com/watch?v=eBGIQ7ZuuiU
-`🧌FUCKINDOITLIVE.gif👹`  → https://www.youtube.com/watch?v=Qy-Y3HJNU_s

## Token Load Bias

At send time, snapshot `ctx.getContextUsage().tokens`. If context is large (TBD threshold), skip light tier — open at medium when the 1-min mark hits.

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

- [ ] What does "verbiagating" mean as a concept — internal name only, or label shown in strip?
- [ ] Breakdancing GIF URL
- [ ] FUCKINDOITLIVE.gif URL
- [ ] Large-context token threshold for tier-bias
- [ ] More corpus items (user retrieving from /btw notes)
