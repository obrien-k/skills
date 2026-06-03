# Mr. Robot — Reference

Command recipes and the lessons behind each rule. SKILL.md carries the principles; this file carries the concrete commands and the gotchas that produced them.

Sources: founding session (orphic-inc/stellar-api, 2026-05-31) and a battle-testing pass across a 24-repo `~/git/` folder (third-party clones, no-remote repos, a 59-branch graveyard, `gh`-named remotes, duplicate clones).

## Phase 0 — Ownership Gate

The single most important guard. Most failure modes are fail-*open* (acting on a repo you shouldn't).

```bash
# Resolve the remote BY NAME — never assume "origin". gh-cloned repos and forks
# use other names (gh, upstream). A hardcoded `origin` check silently fails open:
# a repo whose remote is named `gh` was misread as "no remote" → LOCAL-ONLY → swept.
REMOTE=$(git remote | grep -qx origin && echo origin || git remote | head -1)
URL=$(git remote get-url "$REMOTE" 2>/dev/null)

OWNER=$(printf '%s' "$URL" | sed -E 's#(git@[^:]+:|https?://[^/]+/)##; s#/?\.git$##; s#/.*##')
REPO=$(basename "$URL" .git)
PUSH=$(gh api "repos/$OWNER/$REPO" --jq '.permissions.push' 2>/dev/null)
```

- **No remote at all** → LOCAL-ONLY mode. The repo is yours by definition but has nowhere to push: clean local branches, skip remote deletes / fork sync / pushes.
- **No push rights, or owner isn't you/your org/your fork** → HARD STOP. Activity, stars, recency are never authorization — ownership is.
- **Non-GitHub host** (parse host from `$URL`) → `gh api` doesn't apply. The local-git phases work unchanged; use the forge's CLI (`glab` for GitLab) for push-rights/PRs/remote-deletes, or confirm ownership with the user. Never read an empty `gh` result as "no access" — that fails closed on your own repo.

## Phase 1 — Architecture Detection

Prefer local git (offline, no auth); reach for the host API only for remote-only signal.

```bash
# Default branch — try remote HEAD, then API, then current branch. Never assume main.
DEFAULT=$(git symbolic-ref --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#$REMOTE/##") \
  || DEFAULT=$(gh api "repos/$OWNER/$REPO" --jq '.default_branch' 2>/dev/null) \
  || DEFAULT=$(git branch --show-current)

# Bot/generated repo (>80% bot commits → build artifact, source is elsewhere)
git log -20 --format='%s' | grep -c "^\[bot\]\|^chore(release)\|^Merge pull request"

# Release automation present → tags + CHANGELOG are automated, skip Phases 3 & 5
ls .releaserc* .goreleaser.yml release-please-config.json .bumpversion.cfg 2>/dev/null
# language equivalents: pom.xml (maven-release), Cargo.toml (cargo-release),
# pyproject.toml (setuptools-scm/tbump), package.json (semantic-release/changesets)

# Tag scheme — semver (v1.2.3) vs milestone/build (b1046, defcon32). Respect what exists.
git tag | head

# Maintenance mode — no push in >12 months → confirm archival intent first
git log -1 --format=%cr
```

- **Protected branch set** = `$DEFAULT` + `develop` + `staging` + open-PR branches + long-lived release branches (`3.x`, `release-7x`) + tracking branches (`upstream`, `vendor`). Build this once; every deletion phase excludes it.
- Don't overlay semver on a milestone/build tag scheme — it's correct for embedded/hardware/event repos.

### Merge style + linear-history 🔀

If MCP tools are available, query repo settings directly — prefer whichever access is live in the session over shelling out.

```bash
gh api repos/{owner}/{repo} \
  --jq '{merge: .allow_merge_commit, squash: .allow_squash_merge, rebase: .allow_rebase_merge}'
# required_linear_history on default branch protection
gh api repos/{owner}/{repo}/branches/{default}/protection \
  --jq '.required_linear_history.enabled' 2>/dev/null
```

**This dictates the entire branch-cleanup shape.** A **rebase-only / linear-history** repo cannot absorb a branch that contains merge commits — the rebase can't replay them, so the PR silently won't merge (it sits OPEN, base unchanged, often misread as a flaky button or a permissions issue). On such repos:
- Keep every branch destined for the default branch **linear** (no `Merge branch ...` commits)
- When a branch already has merge commits baked in, don't fix it in place — cut a fresh branch off the target and replay the *content* (squash-merge locally or cherry-pick the non-merge commits), then open the PR from that clean branch
- Squash-only and merge-commit-only repos have their own constraints; match the repo

## Phase 2 — Branch Cleanup

```bash
git fetch -p   # prune stale remote-tracking refs FIRST, always

# Remote deletes via host API — git push --delete hits org branch-protection / token walls
gh api -X DELETE "repos/$OWNER/$REPO/git/refs/heads/<branch>"

# Local: MERGED ONLY. -d refuses unmerged; blanket -D destroys it silently.
git branch --merged "$DEFAULT" | grep -vE "^\*|^  ($DEFAULT|develop|staging)$" \
  | sed 's/^ *//' | xargs -r git branch -d

git branch --no-merged   # list these; force-delete only what the user confirms, one at a time
```

- **Never blanket `git branch -D`.** A graveyard repo hides unmerged work — one test repo had 56 unmerged feature branches that `-D` would have erased.
- `git branch --merged` with no ref checks against *current HEAD*, not `$DEFAULT` — always pass `$DEFAULT` explicitly.
- Check open PRs before deleting: `gh pr list --state open --json headRefName`.

### Author-owned content patterns ✍️

- **Posts/pages:** `_posts/`, `_drafts/`, `content/`, `src/pages/`, `pages/`, `blog/`, `articles/`, standalone `.md`/`.mdx` files at repo root
- **Collections/data:** `_pages/`, `_featured_categories/`, `_data/` (bios, nav, authors), Hugo/Gatsby content collections
- **Templates with prose:** `_includes/`, `_layouts/` partials that embed authored copy
- **Syndication:** `feed.xml`, `atom.xml`, `rss.xml` templates — even if output is generated, the template is authored
- **Meta:** `robots.txt`, `humans.txt`, structured data templates (JSON-LD, OpenGraph)
- **Docs/changelog:** `README.md`, `CHANGELOG.md`, `docs/` prose (not build output)

### History scrubbing 🔥

**`git filter-repo` is a separate install — not a git built-in.** `git --filter-repo` is wrong (that's a git flag); the command is `git filter-repo`. Install first:

```bash
brew install git-filter-repo   # macOS
pip install git-filter-repo    # any platform
```

Then scrub a file from the full commit history:

```bash
# Remove a specific file (e.g. .env) from all history
git filter-repo --path .env --invert-paths

# Force push after — history has been rewritten
git push origin <branch> --force
```

**Graveyard hard stop:** if Phase 2 surfaces committed secrets (`.env`, credentials, API keys), stop before any other cleanup and confirm the user wants to scrub history. filter-repo rewrites every SHA — anyone with a local clone will need to re-clone or hard reset. For a repo about to be archived, that's usually fine; for an active repo, coordinate first.

### OS/editor cruft recipes 🧹

```bash
# Delete untracked OS/editor junk only — never touch tracked files
find <repo> -name .DS_Store -not -path '*/.git/*' -not -path '*/node_modules/*' -delete
# Verify nothing is tracked before deleting
git ls-files | grep -E '\.DS_Store|Thumbs\.db|\.swp$|\.idea'
# If already tracked — unstage from git index
git rm --cached <file>
```

- Prefer **global ignore** (`core.excludesfile`, `~/.config/git/ignore`) for personal OS cruft — covers every repo without polluting `.gitignore`
- Only add to repo `.gitignore` when that's the team convention (committed change — branch/PR on protected repos)
- `.DS_Store` regenerates the instant Finder touches a folder — ignore *first*, then sweep; do both repos in one pass (API + UI clone both collect it)

## Phase 3 — Version Tagging

- Detect first (see SKILL table). Skip entirely if release tooling is present.
- **Annotated tags only** (`git tag -a`); lightweight tags carry no message.
- **Verify the commit exists** in the object store (`git cat-file -t <hash>`) before tagging — cross-repo hashes need `git fetch upstream` first.
- Duplicate tags on one commit (e.g. `v0.4.9` / `v0.4.99`) are valid; alias them in the CHANGELOG.
- Manual retroactive tagging is a last resort (no tooling + personal/archived repo). For active repos, recommend adopting [release-please](https://github.com/googleapis/release-please) instead.

## Phase 4 — Fork Sync

Forks only. Guard before touching anything:

```bash
git remote | grep -qx upstream || echo "no upstream — not a fork, skip Phase 4"
[ -z "$(git status --porcelain)" ] || echo "dirty tree — stash or commit first"

git log "$DEFAULT"...upstream/"$DEFAULT" --left-right   # < fork-only, > upstream-only
git checkout "$DEFAULT" && git merge --ff-only upstream/"$DEFAULT"
git fetch upstream --tags && git push "$REMOTE" --tags   # tags don't sync automatically
```

- **Refuse on a dirty tree** — `checkout`/`merge` carry or clobber uncommitted work.
- **Recreating `develop`: confirm it's fully merged first, then `-d`.** A stale-looking `develop` may hold unmerged commits (one test repo: 7). Never blanket `-D` — this corrects the founding-session note that said "delete and recreate."

## Phase 5 — CHANGELOG

```bash
git log --oneline <prev-tag>..<new-tag>
```

- **Read an existing CHANGELOG before writing — don't clobber it.** Append a new version section; don't regenerate.
- [Keep a Changelog](https://keepachangelog.com/): `Added / Changed / Fixed` per version.
- Lump closely related commits under one bullet; cite hashes only for notable multi-commit eras; compare-links at the bottom.

## Phase 6 — Stub Tracking

- Surface dedicated files first: `TODO.md`, `FIXME.md`, `NOTES.md`.
- Then grep language-agnostic markers: `TODO`/`FIXME`/`HACK`, `raise NotImplementedError`, `todo!()`/`unimplemented!()`, `throw new Error(... not implemented)`, HTTP `501`.
- Worth tracking: live-but-incomplete features — a route returning bare `{}`, a model with no write path. Not broken, just unfinished.
- File issues only with explicit user authorization; otherwise note in memory.
- Retrospective by nature — finds gaps in existing code. Starting fresh? Use [`/tdd`](https://github.com/mattpocock/skills/blob/main/skills/engineering/tdd/SKILL.md) instead.
