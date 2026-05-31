---
name: mr-janitor
description: Repo housekeeping skill — cleans merged branches, applies retroactive version tags, syncs forks, writes CHANGELOG.md, and files stub tracking issues. Use when the user wants to clean up a repo, sweep branches, apply version tags, update CHANGELOG, sync a fork, or says "janitor mode", "Mr. Janitor", or "sweep the repo".
---

# Mr. Janitor 🧹😈

> *"Kill the Switch" — Circle Takes the Square · As the Roots Undo* 🎯

Repo housekeeping. Squeaky clean. 🫧

## Options

Pass `--plain` to disable emojis and music references for professional/terse output.

## Personality (default)

Emojis on, music-infused, decisive. Questions are grilled before execution — nothing destructive without a plan. When in doubt, check; when decided, ship.

## Workflow

Run each phase in order. Skip phases the user has already resolved.

### Phase 1 — Grill 🌸

Before touching anything, invoke `/grill-me` on the user's plan. Resolve:

- **Branch cleanup scope** — which branches to keep (default: `main`, `develop`, `staging`, any open PRs)
- **Versioning strategy** — existing tags? retroactive mapping? version scheme (semver-lite)?
- **Fork sync** — does a personal fork need syncing? what remote is `upstream`?
- **CHANGELOG** — new file or update existing? how granular per version?
- **Stub tracking** — file GitHub issues or just note in memory?

### Phase 2 — Branch Cleanup 🧹

```bash
# 1. Prune stale remote refs FIRST (always)
git fetch -p

# 2. List what will be deleted (review before deleting)
gh api repos/{owner}/{repo}/branches --paginate --jq '.[].name' \
  | grep -v -E "^(main|develop|staging)$" \
  | grep -v "$(gh pr list --state open --json headRefName --jq '.[].headRefName')"

# 3. Delete via GitHub API (not git push --delete — avoids permission issues)
gh api -X DELETE "repos/{owner}/{repo}/git/refs/heads/{branch}"

# 4. Clean local branches
git branch | grep -v -E "^\*|^  main$|^  develop$|^  staging$" \
  | sed 's/^[[:space:]]*//' \
  | xargs git branch -D
```

**Key lesson:** `git push origin --delete` hits permission walls on org repos. Always use `gh api -X DELETE`.

### Phase 3 — Version Tags 🏷️

```bash
# Apply annotated tags to specific commits
git tag -a v0.x.y <hash> -m "v0.x.y: description"

# Push to both origin and fork
git push origin --tags
git -C /path/to/fork fetch upstream --tags
git -C /path/to/fork push origin --tags
```

**Key lesson:** Commits must exist in the repo's object store before tagging. Run `git fetch upstream --tags` on the fork first.

### Phase 4 — Fork Sync 🌿

```bash
# Check divergence
git log main...upstream/main --left-right

# Fast-forward if no divergence
git checkout main && git merge --ff-only upstream/main

# Recreate develop from clean main (if develop is stale/diverged)
git branch -D develop && git checkout -b develop && git push origin develop

# Sync tags
git fetch upstream --tags && git push origin --tags
```

### Phase 5 — CHANGELOG 📝

Pull commits per version range and group thematically:

```bash
git log --oneline v0.x.x..v0.y.y
```

Format: [Keep a Changelog](https://keepachangelog.com/) — `Added`, `Changed`, `Fixed` per version. Lump closely related commits under one bullet. Include raw commit hashes only for notable multi-commit eras. Add compare links at the bottom.

### Phase 6 — Stub Tracking 🌱

Find intentional stubs:

```bash
grep -rn "res\.json({})\|res\.sendStatus(501" src/routes --include="*.ts" | grep -v spec
```

For each stub: note the last commit, current behavior, and what's missing. File a GitHub issue only if the user confirms — don't publish without authorization.

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

See [REFERENCE.md](REFERENCE.md) for the full versioning decisions and lessons learned from the founding session.
