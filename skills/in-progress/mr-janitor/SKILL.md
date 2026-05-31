---
name: mr-janitor
description: Repo housekeeping skill — cleans merged branches, applies retroactive version tags, syncs forks, writes CHANGELOG.md, and files stub tracking issues. Use when the user wants to clean up a repo, sweep branches, apply version tags, update CHANGELOG, sync a fork, or says "janitor mode", "Mr. Janitor", or "sweep the repo".
---

# Mr. Janitor 🧹😈

> *"Kill the Switch" — Circle Takes the Square · As the Roots Undo* 🎯

Repo housekeeping. Squeaky clean. 🫧

> **This skill exists because it shouldn't need to.** Versioning, branch hygiene, and changelogs should be automated and running continuously. If they are — great, skip those phases. Where Mr. Janitor shines: **end-of-sprint sweeps** to consolidate a team's disparate commits into coherent changelog entries, clean up the branch graveyard, and give the repo a consistent pulse before the next cycle starts.

## Options

Pass `--plain` to disable emojis and music references for professional/terse output.

## Personality (default)

Emojis on, music-infused, decisive. Questions are grilled before execution — nothing destructive without a plan. When in doubt, check; when decided, ship.

## Workflow

Run each phase in order. Skip phases the user has already resolved.

### Phase 0 — Ownership Gate 🚦 (hard stop)

**Run this before anything else. Destructive housekeeping on a repo you don't control is the worst failure mode.**

```bash
# Resolve the remote by NAME first — never assume it's called "origin".
# Repos cloned via `gh`, forks, or custom setups use other names (gh, upstream…).
REMOTE=$(git remote | grep -qx origin && echo origin || git remote | head -1)
URL=$(git remote get-url "$REMOTE" 2>/dev/null)

if [ -z "$URL" ]; then
  # Genuinely no remote → purely local repo. Yours by definition, but there's
  # nowhere to push: run LOCAL-ONLY mode. Phase 2 cleans local branches,
  # Phases 3-5 can't push (tags/CHANGELOG stay local), Phase 4 is N/A.
  echo "no remote — LOCAL-ONLY mode (skip remote deletes, fork sync, and pushes)"
else
  OWNER=$(printf '%s' "$URL" | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#/?\.git$##; s#/.*##')
  REPO=$(basename "$URL" .git)
  PUSH=$(gh api "repos/$OWNER/$REPO" --jq '.permissions.push' 2>/dev/null)
  VIEWER=$(gh api user --jq '.login' 2>/dev/null)
fi
```

**Note the remote name (`$REMOTE`) — it may not be `origin`.** Every later `git push`/`git fetch`/branch-delete must use `$REMOTE`, not a hardcoded `origin`, or it targets the wrong place (or nothing).

**Decision:**
- **No remote** → local-only mode (above). Proceed, but every remote operation is skipped.
- **Remote exists and `push` is `false`/empty, or owner isn't you/your org/your fork → HARD STOP.** This is a third-party clone (an upstream you track for reference). Report: *"This is a clone of `{owner}`'s repo and you don't have push rights — refusing to sweep. I can offer read-only observations only."* An active, non-bot, non-archived repo is **not** sufficient authorization — ownership is.
- **Remote exists and `push` is `true`** → proceed. If it's a fork you own, handle the upstream in Phase 4.

### Phase 1 — Grill 🌸

Before grilling, run architecture detection to avoid prescribing the wrong work. **Prefer local git commands** (`git symbolic-ref`, `git tag`, `git log`, `ls`) — they work offline and need no auth. Use `gh api` only for signal that's genuinely remote-only (push rights, `pushed_at`, open PRs):

```bash
# 1. Resolve the real default branch — never assume main/master.
#    Try the remote's HEAD, then the API, then fall back to the current branch
#    (covers local-only repos and clones with no remote HEAD ref set).
DEFAULT=$(git symbolic-ref --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#$REMOTE/##") \
  || DEFAULT=$(gh api "repos/$OWNER/$REPO" --jq '.default_branch' 2>/dev/null) \
  || DEFAULT=$(git branch --show-current)

# 2. Check for bot-driven commit history (>80% bot commits = generated repo)
gh api "repos/{owner}/{repo}/commits?per_page=20" --jq '.[].commit.message' \
  | grep -c "^\[bot\]\|^chore(release)\|^Merge pull request"

# 3. Check for automated release tooling (language-agnostic)
gh api repos/{owner}/{repo}/contents --jq '.[].name' \
  | grep -E "\.releaserc|release\.config|\.goreleaser|release-please-config|\.bumpversion|RELEASING"
# Also check: pom.xml (maven-release-plugin), Cargo.toml (cargo-release), pyproject.toml (setuptools-scm, tbump)

# 4. Detect existing tag scheme — semver or something else?
gh api repos/{owner}/{repo}/tags --paginate --jq '.[].name' | head -10

# 5. Check for long-lived release branches AND fork-tracking conventions
gh api repos/{owner}/{repo}/branches --paginate --jq '.[].name' \
  | grep -E "^\d+\.x$|^release-\d|^upstream$|^vendor$"

# 6. Maintenance mode check
gh api repos/{owner}/{repo} --jq '.pushed_at'
# If >12 months ago: confirm archival intent before doing anything
```

**If >80% of recent commits are bot-generated:** flag as build artifact. Ask: *"Is the real source in a separate repo? Should I look there instead?"* Skip retroactive tags and CHANGELOG.

**If release tooling detected:** skip Phase 3 and Phase 5 — both automated. Tell the user.

**If tags don't match `v?\d+\.\d+`:** treat as event/milestone tagging scheme. Respect it — don't overlay semver.

**If long-lived release branches (`3.x`, `release-7x`) or tracking branches (`upstream`, `vendor`) detected:** add to protected list.

**If last push >12 months ago:** ask whether this is an archival sweep before proceeding.

The protected branch baseline is always: `{default_branch}` + `develop` + `staging` + open PR branches + any of the above.

Run [`/grill-me`](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md) on the housekeeping plan. Decision branches to resolve:

- **Branch cleanup scope** — which branches to keep (default branch from API, `develop`, `staging`, release branches, any open PRs)
- **Versioning strategy** — existing tags? scheme (semver or milestone)? automated tooling present?
- **Fork sync** — does a personal fork need syncing? what remote is `upstream`?
- **CHANGELOG** — new file or update existing? how granular per version? automated tooling present?
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

# 4. Clean local branches — MERGED ONLY, never force by default.
#    Protected set = resolved default branch ($DEFAULT from Phase 1) + develop + staging.
PROTECTED="${DEFAULT:-main}|develop|staging"
git branch --merged | grep -vE "^\*|^  ($PROTECTED)$" \
  | sed 's/^[[:space:]]*//' | xargs -r git branch -d   # -d = safe, refuses unmerged

# 5. UNMERGED branches are NOT auto-deleted. List them for explicit review:
git branch --no-merged
#    Only force-delete (-D) ones the user confirms are abandoned, one at a time.
```

**Key lesson:** `git push origin --delete` hits permission walls on org repos. Always use `gh api -X DELETE`.

**Key lesson:** Use `git branch -d` (merged-only, refuses to drop unmerged work), never blanket `-D`. A repo with real branch debt (e.g. 56 unmerged feature branches) will lose work silently under `-D`. Unmerged branches require per-branch confirmation.

### Phase 3 — Version Tags 🏷️

**Detect before acting:**

| Signal | Action |
|---|---|
| `.releaserc`, `.goreleaser.yml`, `release-please-config.json`, `Cargo.toml` + release CI | Tags are automated — skip this phase, tell the user |
| Tags exist and are consistent | Confirm scheme, offer to catch up any gaps only |
| No tags, no tooling, active repo | Recommend adopting tooling ([release-please](https://github.com/googleapis/release-please) is language-agnostic) rather than manual tagging |
| No tags, no tooling, personal/archived repo | Manual retroactive tagging as last resort (below) |

**Last-resort manual tagging:**

```bash
# Apply annotated tags to specific commits
git tag -a v0.x.y <hash> -m "v0.x.y: description"

# Push tags
git push origin --tags
```

**Key lesson:** Commits must exist in the repo's object store before tagging. Run `git fetch upstream --tags` on the fork first if working with a fork.

### Phase 4 — Fork Sync 🌿

**Guard first — this phase only applies to forks, and never on a dirty tree:**

```bash
# Skip the whole phase if there's no upstream remote (this isn't a fork)
git remote | grep -qx upstream || { echo "no upstream — not a fork, skip Phase 4"; }

# Refuse to proceed with uncommitted work — checkout/merge would carry or clobber it
[ -z "$(git status --porcelain)" ] || { echo "dirty tree — stash or commit first"; }
```

```bash
# Check divergence (use resolved $DEFAULT, not hardcoded main)
git log "$DEFAULT"...upstream/"$DEFAULT" --left-right

# Fast-forward if no divergence
git checkout "$DEFAULT" && git merge --ff-only upstream/"$DEFAULT"

# Sync tags
git fetch upstream --tags && git push origin --tags
```

**Recreating `develop` from clean `$DEFAULT`?** Only if `develop` is confirmed fully merged. **Never blanket `git branch -D develop`** — force-delete ignores merge state and a stale-looking `develop` may carry unmerged commits (seen in testing: 7 unmerged). Verify first:

```bash
git branch --merged "$DEFAULT" | grep -qx '  develop' \
  && git branch -d develop && git checkout -b develop && git push origin develop \
  || echo "develop has unmerged commits — review before recreating"
```

### Phase 5 — CHANGELOG 📝

Pull commits per version range and group thematically:

```bash
git log --oneline v0.x.x..v0.y.y
```

Format: [Keep a Changelog](https://keepachangelog.com/) — `Added`, `Changed`, `Fixed` per version. Lump closely related commits under one bullet. Include raw commit hashes only for notable multi-commit eras. Add compare links at the bottom.

### Phase 6 — Stub Tracking 🌱

First, check for dedicated tracking files before grepping:

```bash
# Dedicated files take priority — surface these first
ls TODO.md FIXME.md NOTES.md HACKING.md 2>/dev/null
```

Then find intentional stubs using language-agnostic markers:

```bash
# Universal: TODO/FIXME/STUB/HACK comments and not-implemented throws
grep -rn "TODO\|FIXME\|STUB\|HACK\|NOT IMPLEMENTED\|raise NotImplementedError\|todo!()\|unimplemented!()\|throw new Error.*not implemented" \
  --exclude-dir="{node_modules,.git,vendor,dist,build,__pycache__}" \
  --exclude="*.lock" .

# HTTP-level stubs (language-agnostic: 501 status = not implemented)
grep -rn "501\|NotImplemented" . \
  --exclude-dir="{node_modules,.git,vendor,dist}" \
  --exclude="*.lock"
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
