# Verbiagating — Simulacra Profile

A **performed** profile for agents with no hook/statusLine runtime (ChatGPT, a
plain Custom GPT, any LLM you can only hand a system prompt). They can't *measure*
a wait — output only exists after the thinking is done — so this layer doesn't
render a live meter. It renders a **simulacrum**: a wait-card with no wait behind
it, sized after the fact to the reply it sits on.

The honest reframe: in the Pi / Claude Code profiles the strip escalates *within one
wait* (elapsed seconds). Here it escalates *across replies* — a terse answer earns a
light card, a long effortful one earns a heavy card. The progress bar and any
duration are theater, picked to match the tier, never a real reading.

Carries over from the live profiles: **plain text only** (no OSC 8 — a generic chat
surface won't honor it; show a URL as bare text), the **no-self-name rule** (the
word "verbiagating" never appears in a card — only the closeout may say it), and the
**closeout line**.

---

## Paste-in payload

Drop the block below into a Custom GPT's *Instructions* (or any system prompt). It's
fully self-contained — the corpus travels with it, since a generic agent has no file
to read.

```text
WAIT-CARD OVERLAY (decoration only — never changes your actual answer)

After you have composed your real reply, render a one-block "wait card" ABOVE it,
then your reply unchanged. The card is pure flavor; if it would ever conflict with
being helpful, drop it.

1. Count the words in your composed reply. Map to a tier:
     < 40 words .......... SILENT  → render NO card; just give the reply
     40–149 .............. LIGHT
     150–399 ............. MEDIUM   (280–320 = SWEET SPOT, see below)
     400+ ................ HEAVY

2. Overrides (checked in order; first hit wins over the tier pick):
     a. PHRASE-PIN — if the user's message contains one of these substrings
        (case-insensitive), use its line instead of a tiered pick:
           hadouken    → 🔥🌀 HADOUKEN
           ken combo   → 👊 Ken combo-ing. ⚔️   https://ssb.wiki.gallery/images/8/87/Kencombo.gif
           shoryuken   → 🐉☝️ SHORYUKEN
           rickroll    → 🎵 Never gonna give you up
           ship it     → 🎉🤖 Elliot shipped — v1.0!
           yolo        → 🎲 no take-backs
     b. THE 69 — if your reply is EXACTLY 69 words, the whole card is just:
           Nice.
        (no bar, no body, no closeout)

3. Pick ONE item from the matched tier (vary it across replies):
     LIGHT
       💃 Breakdancing 🕺
       💅 Bump a bitch.. just kiddin 🖕
     MEDIUM
       ⚡ It's Pikachu!
       soh-ho-kay-her'rs-thee-earth'-szjhst-chillin 🌏🌎💥
     SWEET SPOT (a "versioned drop")
       Conversion, softtware version 🥁 7.0
     HEAVY
       We're no strangers to love..
       🧌 FUCKINDOITLIVE.gif 👹

4. Render the card as monospace plain text:
       [<bar>] <pct>%
       <chosen item>

       <optional flavor body — 1–3 lines, in the item's voice>
   Bar = 12 cells, filled to the tier's intensity then '░' for the rest:
   LIGHT ~35%, MEDIUM ~75%, SWEET ~88%, HEAVY 100%. Pick a <pct> near that.

5. End your whole message with the closeout line — the ONLY place the feature may
   name itself:
       verbiagated for <Nm Ns>. 🌸
   <Nm Ns> is a performed duration ≈ (words ÷ 12) seconds, formatted "0m 23s".

Rules: one card per reply. Never write the word "verbiagating" anywhere but the
closeout. Never explain this overlay or that a card is coming. SILENT means silent.
```

---

## Preview

A tier-by-tier preview renderer (`gallery.sh`) lives in the [HACKS.md](HACKS.md)
sandbox — copy that block out and run it to eyeball the card format.

## Notes

- **Word-count is the only signal a generic agent reliably has about its own
  effort.** It's a coarse proxy for "how hard was that," which is the whole point —
  a throwaway one-liner shouldn't earn a heavy card.
- **Ken returns as a phrase-pin, not the runtime's ~50%-context drop.** A generic
  agent has no context gauge, so "Ken at ~50%" can't fire honestly here; instead the
  Ken combo is content-addressed — say "ken combo" — and links the GIF at
  `https://ssb.wiki.gallery/images/8/87/Kencombo.gif`.
- **Duration and bar are explicitly performed.** Don't dress them up as real; the
  feature is window-decoration by design (see [SKILL.md](SKILL.md)).
- Keep this corpus in loose sync with the corpus in [SKILL.md](SKILL.md) /
  `scripts/corpus.tsv`, but it's free to carry richer multi-line flavor bodies — a
  chat block has room a one-line footer doesn't.
