Quickstart:

```bash
npx skills add obrien-k/skills --skill=mr-robot
```

```bash
npx skills update mr-robot
```

[Source](https://github.com/obrien-k/skills/tree/main/skills/engineering/mr-robot)

## What it does

`mr-robot` is the repo-branch-drift maintenance SysOp — it sweeps a repository back into a coherent, releasable state: prunes merged branches, applies retroactive version tags, syncs forks, writes the CHANGELOG, files stub tracking issues, reconciles the open issues against the code, and runs a release gate. The whole run is a single **sweep** of ten ordered phases, and it does nothing destructive without a plan you've confirmed. The defining constraint is that the sweep is **fail-closed**: an unbucketed finding is a show-stopper by default, so a release only cuts once every finding is named, owned, and bucketed — the gate never waves through what it hasn't accounted for.

It is a fork-only skill (it lives in `obrien-k/skills`, not upstream `mattpocock/skills`), and it is deliberately narrow about its lane: it keeps the *repo* honest — branches, tags, claims, gates — and refers every *product* question (is this promise right? is this a show-stopper for users?) to a product-advocacy skill, when one is installed, rather than answering it itself.

## When to reach for it

- **Invocation mode.** Type `/mr-robot`, or the agent reaches for it automatically when a task fits — cleaning up a repo, sweeping branches, catching up version tags, syncing a fork, reconciling issues, or checking for show-stoppers before a release. It also answers to `Elliot`, `janitor mode`, "sweep the repo", "phase 9", "phase 10", "kill the switch", and "such great heights".
- **Trigger boundary.** Reach for it when a repo has drifted — stale branches, an out-of-date CHANGELOG, docs that no longer match the code, a fork behind upstream, or a release you want gated. For reviewing whether one *diff* implements its spec, use `/code-review` instead; for whether a feature is right *for users*, use a product-advocacy skill.

## Prerequisites

None to install. In use, a sweep opens a **Sweep Ledger** — a running record of findings and cross-artifact claims — and persists any pause/resume handoff into the repo as a `.handoff-<topic>.md` dotfile (never `/tmp`, never committed), via `scripts/pause-handoff.sh`. Remote operations (deleting branches, closing issues) are gated behind an Ownership Gate that fails closed unless the resolved context greenlights them.

## The sweep is a setlist

The ten phases run front to back, one track each — Phase 1 drops the needle, Phase 10 reaches the summit:

`0` Ownership Gate → `1` Grill → `2` Branch Cleanup → `3` Version Tags → `4` Fork Sync → `5` CHANGELOG → `6` Stub Tracking → `7` Docs Rundown → `8` Doc Topology → `9` Reconcile → `10` Such Great Heights.

The leading word is **sweep**: everything is collected into the ledger as it goes, held in tension at the Reconcile pass (contradictions between a PRD, an ADR, a code comment, and the implementation all surface here), and discharged at the release gate. Nothing enters a later phase from memory — only from the ledger.

The other half of the character is **deference**. A sweep is a coordinator, not a monolith: it hands grilling to `/grill-me`, diff-level spec conformance to `/code-review`, merge conflicts to `/resolving-merge-conflicts`, documented-slice descent to `/tdd`, terminology sharpening to `/grill-with-docs`, and handoff prose to `/handoff`. It owns only the work no other skill does — the repo-wide branch/tag/claims sweep and the fail-closed gate.

## It's working if

- Every destructive step pauses for your confirmation first — no branch deleted, issue closed, or tag cut silently.
- Findings accumulate in the Sweep Ledger with phase labels, and product-shaped ones are flagged `OUT-OF-PURVIEW` and handed off rather than answered.
- The release gate refuses to cut while any finding is unbucketed — you see it name the show-stopper, not skip it.

## Where it fits

Periodic maintenance plus a release gate — run it when a repo has drifted or before you ship, not on every change. It sits at the end of the flow the other skills feed: they build and review the work; `mr-robot` sweeps the repository around it into a releasable state, deferring to `/code-review`, `/resolving-merge-conflicts`, and a product-advocacy skill at the seams where another skill owns the call.
