# Mr. Robot — Reference

Command recipes and the lessons behind each rule. SKILL.md carries the principles; this file carries the concrete commands and the gotchas that produced them.

Sources: founding session (orphic-inc/stellar-api, 2026-05-31) and a battle-testing pass across a 24-repo `~/git/` folder (third-party clones, no-remote repos, a 59-branch graveyard, `gh`-named remotes, duplicate clones).

**Design rationale.** Why Mr. Robot is a skill + bash scripts (and *not* an MCP): determinism is the line — judgment stays in the skill, deterministic mechanics are guard-scripts the skill calls; destructive ops are API-only and enforced by a `git-guardrails` hook, not an MCP. The MCP is deferred indefinitely. See [rocky-pi ADR-0002](https://github.com/obrien-k/rocky-pi/blob/main/docs/adr/0002-mr-robot-skill-mcp-split.md).

## Phase 0 — Sweep Context + the Ownership Gate

The single most important guard. Most failure modes are fail-*open* (acting on a repo you shouldn't). Resolve it **once** with [`scripts/resolve-context.sh`](scripts/resolve-context.sh) — a read-only resolver that emits the **Sweep Context** (the resolved facts every later phase consumes) with the **Ownership Gate** verdict in its `RC_MODE` field. Don't re-derive `$RC_REMOTE`/`$RC_DEFAULT` per phase; source it here and reuse.

```bash
eval "$(scripts/resolve-context.sh)"   # → RC_MODE RC_REMOTE RC_HOST RC_OWNER RC_REPO RC_DEFAULT
# (or MR_ROBOT_REPO=<repo-root> scripts/resolve-context.sh to resolve a repo you're not cd'd into)
```

The resolver is **strictly read-only** (git reads + `gh api` GETs, never a mutation) — safe to run anytime; that read-only property is also how it's verified, absent a test runner in this repo. It resolves the remote **by name** — never assumes `origin`. A gh-cloned repo or fork uses other names (`gh`, `upstream`); a hardcoded `origin` check silently fails open (a repo whose remote is named `gh` was misread as "no remote" → LOCAL-ONLY → swept).

**Ownership Gate verdicts (`RC_MODE`) — fail-closed: anything not positively confirmed yours-and-pushable is NOT `proceed`.**

| `RC_MODE` | Signal | Mr. Robot does |
|---|---|---|
| `local-only` | no remote — yours by definition, nowhere to push | clean local branches; skip remote deletes / fork sync / pushes |
| `proceed` | GitHub host, `permissions.push == true` | full treatment, using `$RC_REMOTE` |
| `hard-stop` | GitHub, push false / empty / API-error, or unparseable host | read-only observations only — activity, stars, recency are never authorization; ownership is |
| `needs-confirm` | non-GitHub host (`$RC_HOST`) | `gh api` doesn't apply; use that forge's CLI (`glab` for GitLab) or confirm ownership with the user, then proceed |

## Phase 1 — Architecture Detection

Prefer local git (offline, no auth); reach for the host API only for remote-only signal.

```bash
# Default branch already resolved into $RC_DEFAULT by the Sweep Context (Phase 0).

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

- **Protected branch set** = `$RC_DEFAULT` + `develop` + `staging` + open-PR branches + long-lived release branches (`3.x`, `release-7x`) + tracking branches (`upstream`, `vendor`). Assemble it once from the Sweep Context (kept out of the resolver — it carries judgment); every deletion phase excludes it.
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
gh api -X DELETE "repos/$RC_OWNER/$RC_REPO/git/refs/heads/<branch>"

# Local: MERGED ONLY. -d refuses unmerged; blanket -D destroys it silently.
git branch --merged "$RC_DEFAULT" | grep -vE "^\*|^  ($RC_DEFAULT|develop|staging)$" \
  | sed 's/^ *//' | xargs -r git branch -d

git branch --no-merged   # list these; force-delete only what the user confirms, one at a time
```

- **Never blanket `git branch -D`.** A graveyard repo hides unmerged work — one test repo had 56 unmerged feature branches that `-D` would have erased.
- `git branch --merged` with no ref checks against *current HEAD*, not `$RC_DEFAULT` — always pass `$RC_DEFAULT` explicitly.
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

### Local-only *persistent* files (handoffs, resume notes) 📌

A handoff/resume doc must outlive a reboot but must **never** enter commit history. `/tmp` and `$TMPDIR` are wiped on macOS boot — the worst possible time to lose a resume doc.

The enforced guard — [`scripts/pause-handoff.sh`](scripts/pause-handoff.sh) — does this safely: it (a) refuses to persist under `/tmp`/`$TMPDIR`, (b) relocates the draft into the repo as a dotfile, and (c) appends the per-clone `.git/info/exclude` entry, then verifies git neither tracks nor surfaces the file before reporting "paused safe".

```bash
# Scripted (preferred) — run from inside the target repo, or set MR_ROBOT_REPO=<repo-root>:
scripts/pause-handoff.sh <topic> /tmp/handoff.md   # relocate an existing draft
some-generator | scripts/pause-handoff.sh <topic>  # or read the body from stdin

# Manual equivalent, if you can't reach the script:
mv /tmp/handoff.md <repo>/.handoff-<topic>.md                 # dotfile → Jekyll/static builders ignore it
printf '\n# local-only resume handoff (never commit)\n.handoff-<topic>.md\n' >> <repo>/.git/info/exclude
git status --short                                             # MUST NOT list the handoff
```

- `.git/info/exclude` = the per-clone "gitexclude": ignores like `.gitignore` but is **itself untracked**, so the rule never reaches commit history (and `git add -A` won't pick the file up).
- Distinct from global ignore above: global ignore is for *disposable* cruft; this is for files you want to *keep and reference* locally.
- Plan files under `~/.claude/plans/` already persist (home dir, not temp) — safe there; it's the `/tmp` handoff that needs relocating.

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

git log "$RC_DEFAULT"...upstream/"$RC_DEFAULT" --left-right   # < fork-only, > upstream-only
git checkout "$RC_DEFAULT" && git merge --ff-only upstream/"$RC_DEFAULT"
git fetch upstream --tags && git push "$RC_REMOTE" --tags   # tags don't sync automatically
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
- Retrospective by nature — finds gaps in existing code. Starting fresh? Use `/tdd` instead.

## Phase 7 — Docs Rundown

The README is the navigation hub. Run a docs-coherence pass before declaring a repo clean / before TDD.

### Find before you write — docs may be stranded

Canonical docs often live on the default branch while feature code lives on `develop`; a doc you're about to "create" may already exist there. Always `git show <default>:docs/...` and search issues/PRs **before minting a new spec** — a fresh number off the wrong branch duplicates the doc and collides numbering. (Learned the hard way: a duplicate PRD-01 + a colliding ADR-0002 authored off `develop` because the originals were stranded on `main`.)

### Cross-reference both ways

PRDs cite the ADRs that decide them; ADRs cite the PRD they serve; both cite the implementing issues/PRs. The latest PRD should reference every ADR in its orbit; back-fill older PRDs that gained an ADR later. Dangling or one-directional links are a finding.

### Numbering discipline

Confirm the PRD/ADR numbering owner and existing sequence before adding. Reserved-but-unwritten numbers (an ADR referenced by an issue but not yet filed) still count as taken.

### Record decisions, map to code, descend

Anything *decided* in the sweep (versioning, allowed merge style, migration/scoring approach) → an ADR; a new capability → a PRD. Pin ambiguous spec as executable interpretation and flag it, rather than leaving it implicit. A good PRD is a decision-tree into *existing* testable worktrees, not greenfield prose — note where each concept already lives in code, then hand the slice to `/tdd` for the red-green descent. The end-of-sweep trio: `/doc-coauthoring` (authoring), `/grill-with-docs` (stress-test vs the domain model), `/tdd` (descend to tests). Keep specs lean; don't spec-hell.

## Phase 8 — Doc Topology & Community Standards

The end-game phase. Phase 7 made sure each feature is documented *somewhere*; Phase 8 asks whether the documents themselves are *well-placed*, and whether a community — not just a codebase — has its standards written down. Runs in conjunction with Phase 0: the ownership gate fires a doc-topology pre-scan, and Phase 8 closes the loop with the full reconciliation.

### Doc-topology checklist 🗺️

- **Where do docs live?** Map the doc surfaces — `README.md`, `docs/`, ADRs, PRDs, `CONTRIBUTING.md`, wiki, in-repo `CONTEXT.md`. Is the layout legible to a newcomer, or does institutional knowledge live only in commit messages?
- **What exists where?** Inventory every doc file and where it sits. A spec under `src/` next to code, an ADR loose at repo root, a `docs/` folder with one stale file — all topology smells.
- **Placement within the infrastructure.** Is each doc where a reader would look for it? Setup steps belong in `CONTRIBUTING.md`/README, decisions in `docs/adr/`, API contracts beside the generated spec. Move misfiled docs to where they're discoverable.
- **Core-beliefs re-test.** Re-read the repo's foundational docs (README intro, top ADRs, CONTEXT.md) against the *latest* changes — not just the docs for the change under review. Did this sweep quietly invalidate a stated principle? Flag drift.
- **Cross-repo canonical-source check.** When the same wiki/docs/standards appear in multiple repos, confirm which copy is canonical and stub the mirror with a pointer — cross-reference Phase 7's [canonical content source check](SKILL.md#phase-7--docs-rundown-). A Community-Standards doc reproduced as a worked example elsewhere must say so, and name its home.

### Community-Standards boilerplate

The 5-section template below is **never offered proactively** — it's reference material for when the user *explicitly* asks to draft community policy (never auto-created). It's a starting frame for a community that wants to write down what it stands for:

```
1. Statement of Intention & Values: This section establishes why your group is a "community" rather than just a "group of interests". "Our community exists to foster mutual concern, trust, and shared growth among all members. We are united by our shared belief in [Insert Core Value 1] and [Insert Core Value 2]. We measure our success not by self-gain, but by how we advance the welfare of one another."

2. The Boundary Principle: This clarifies who belongs and sets expectations for behavioral safety. "Membership is a recognized demarcation that allows our members to feel safe. While we welcome Explorers and Visitors to designated public spaces, full membership requires shared alignment with our values. Members are expected to treat others as they wish to be treated in real life and respect the privacy of their peers."

3. Moral Prescriptions & What We Protect: This defines intolerable behavior and states what the community defends. "What we protect: We protect the dignity, safety, and mutual respect of all members. What is intolerable: Personal attacks, harassment, or using the community strictly for self-promotion without contribution to the broader welfare are unacceptable. We reserve the right to respectfully hand down consequences or separate individuals from the community whose actions threaten the safety of the whole."

4. Pathways for Belonging (Inner Rings): This provides a path for members to deepen their participation and serve others. "Healthy communities make paths for members to grow and deepen their participation over time. Members have the opportunity to take on responsibilities, organize rituals, mentor newer members, and advance to leadership (Elder) roles based on demonstrated maturity and selfless service to the group."

5. Community Contact & Governance: This establishes who manages the community, as outlined in guides like CommunityRule. "This community is supported by [leadership title, e.g., an elected board/principal elders] who guide our values and officiate our shared rituals. For support, questions, or to report a violation, please contact the community managers directly at [Contact Email]."
```
