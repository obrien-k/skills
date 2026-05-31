---
name: mr-janitor
description: Repo housekeeping skill — cleans merged branches, applies retroactive version tags, syncs forks, writes CHANGELOG.md, and files stub tracking issues. Use when the user wants to clean up a repo, sweep branches, apply version tags, update CHANGELOG, sync a fork, or says "janitor mode", "Mr. Janitor", or "sweep the repo".
---

# Mr. Janitor 🧹😈

> *"Kill the Switch" — Circle Takes the Square · As the Roots Undo* 🎯

Repo housekeeping. Squeaky clean. 🫧

> **This skill exists because it shouldn't need to.** Versioning, branch hygiene, and changelogs should be automated and running continuously. If they are — skip those phases. Where Mr. Janitor shines: **end-of-sprint sweeps** that consolidate a team's scattered commits into a coherent changelog, clear the branch graveyard, and give the repo a consistent pulse before the next cycle.

## Options

Pass `--plain` to disable emojis and music references for terse output.

## Personality (default)

Emojis on, music-infused, decisive. Grill before executing — nothing destructive without a plan. When in doubt, check; when decided, ship.

## Workflow

These are principles, not a script. Resolve the actual remote name, host, and branch from the repo in front of you — don't assume `origin`, GitHub, or `main`. Run phases in order; skip what the user has resolved. Detailed recipes and the lessons behind each rule live in [REFERENCE.md](REFERENCE.md).

### Phase 0 — Ownership Gate 🚦 (hard stop)

Confirm you're allowed to touch this repo before anything destructive — the worst failure is sweeping a repo you don't control.

- **No remote** → LOCAL-ONLY mode: clean local branches, skip every remote op (deletes, fork sync, pushes).
- **No push rights, or the owner isn't you / your org / your fork** → HARD STOP; offer read-only observations only. Activity, stars, and recency are never authorization — ownership is.
- **Non-GitHub host** (GitLab, Bitbucket, self-hosted) → local-git phases work unchanged; use that host's CLI/API for push-rights, PRs, and remote deletes, or confirm with the user. Never read an empty `gh` result as "no access."
- **Push rights confirmed** → proceed, and use the resolved remote name (not `origin`) for every later command.

### Phase 1 — Grill 🌸

Detect the repo's shape before prescribing work. Prefer local git (offline, no auth); use the host API only for remote-only signal (push rights, last-push date, open PRs). Resolve and respect:

- **Default branch** — query it, never assume. Protected set = default + `develop` + `staging` + open-PR branches + any release/tracking branches below.
- **Bot/generated repo** (>80% `[bot]`/release-bot commits) → build artifact; ask if the real source is elsewhere, skip tags + CHANGELOG.
- **Release automation** (`.releaserc`, `.goreleaser`, `release-please`, or language equivalents) → tags + CHANGELOG are automated; skip Phases 3 and 5.
- **Tag scheme** — semver vs. milestone/build (`b1046`, `defcon32`). Respect what exists; don't overlay semver on a non-semver scheme.
- **Long-lived release branches** (`3.x`, `release-7x`) and **tracking branches** (`upstream`, `vendor`) → protect them.
- **Maintenance mode** (no push in >12 months) → confirm this is an archival sweep first.

Then run [`/grill-me`](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md) on the plan: branch scope, versioning strategy, fork sync, CHANGELOG granularity, stub tracking.

### Phase 2 — Branch Cleanup 🧹

1. Prune stale remote refs first (`git fetch -p`).
2. Delete remote branches via the host API (`git push --delete` hits permission walls on org repos), excluding the protected set.
3. **Local branches: merged-only (`git branch -d`) — never blanket `-D`.** Force-delete silently destroys unmerged work, and a graveyard repo can hide dozens of unmerged feature branches. List `--no-merged` and force-delete only what the user confirms abandoned, one at a time.

### Phase 3 — Version Tags 🏷️

Detect before acting:

| Signal | Action |
|---|---|
| Release tooling present (`.releaserc`, `.goreleaser`, `release-please`, etc.) | Automated — skip this phase, tell the user |
| Tags exist and are consistent | Confirm scheme, offer to catch up gaps only |
| No tags, no tooling, active repo | Recommend adopting tooling ([release-please](https://github.com/googleapis/release-please) is language-agnostic) over manual tagging |
| No tags, no tooling, personal/archived repo | Manual retroactive annotated tags as last resort |

Manual tagging is the last resort only — annotated tags (`git tag -a`), then push. Commits must already exist in the object store (fetch from the fork's upstream first if cross-repo).

### Phase 4 — Fork Sync 🌿

Forks only. **Guard:** skip if there's no `upstream` remote; refuse on a dirty tree (checkout/merge would clobber uncommitted work). Then check divergence, fast-forward `merge --ff-only upstream/<default>`, and sync tags. Recreating `develop` requires a confirmed-merged check first — **never blanket `-D`**, which hides unmerged commits.

### Phase 5 — CHANGELOG 📝

Group commits per version range thematically — [Keep a Changelog](https://keepachangelog.com/): Added / Changed / Fixed. **Read an existing CHANGELOG before writing — don't clobber it.** Lump closely related commits under one bullet; cite hashes only for notable multi-commit eras; compare-links at the bottom.

### Phase 6 — Stub Tracking 🌱

Surface dedicated tracking files first (`TODO.md`, `FIXME.md`, `NOTES.md`), then grep language-agnostic markers (`TODO`/`FIXME`/`HACK`, not-implemented throws, HTTP 501). For each stub: last commit, current behavior, what's missing. File issues only with the user's confirmation — don't publish unprompted.

---

## Playlist 🎵

*The full Mr. Janitor setlist — for when the sweep takes a while:*

| | Track | Artist | Album |
|---|---|---|---|
| 🪕🎭 | Idioteque | Amanda Palmer | *...Performs Radiohead On Her Magical Ukelele* |
| 🌊🎙️ | The Rip | Portishead | *Third* |
| ʕ⁎̯͡⁎ʔ🐱 | Yellow Cat (Slash) Red Cat | Say Anything | *...Is a Real Boy* |
| 🔁🎯 | Kill the Switch | Circle Takes the Square | *As the Roots Undo* |

---

See [REFERENCE.md](REFERENCE.md) for command recipes and the lessons behind each rule.
