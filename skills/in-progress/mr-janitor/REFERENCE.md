# Mr. Janitor — Reference

Lessons and decisions from the founding session (orphic-inc/stellar-api, 2026-05-31).

## Branch Cleanup Gotchas

- **Always `git fetch -p` first.** Stale local remote-tracking refs cause `git push --delete` to error with "remote ref does not exist" even when some deletes succeed.
- **Use `gh api -X DELETE` not `git push origin --delete`.** Org repos often block the git protocol delete due to branch protection or token scope. The GitHub API respects your `gh` token directly.
- **Check open PRs before deleting.** Exclude any branch with an open PR: `gh pr list --state open --json headRefName`.
- **Keep `main`, `develop`, `staging` by default.** These are environment branches, not feature branches.

## Fork Sync Gotchas

- **Check divergence with `git log main...upstream/main --left-right`** before merging. `<` = fork-only, `>` = upstream-only.
- **Fork-specific commits** (CI workflows, fork-level config) should sit on top of upstream — fast-forward is the right merge strategy.
- **`develop` on a fork** is often stale or diverged. Cleanest fix: delete and recreate from `main`.
- **Tags don't sync automatically.** After pushing tags to `origin`, do `git fetch upstream --tags && git push origin --tags` on the fork clone separately.

## Version Tagging

- **Annotated tags only** (`git tag -a`). Lightweight tags don't carry messages.
- **Verify commit exists** in the target repo's object store (`git cat-file -t <hash>`) before tagging. Cross-repo hashes don't transfer without `git fetch upstream`.
- **Duplicate tags on same commit** (e.g. `v0.4.9` and `v0.4.99`) are valid but note them as aliases in CHANGELOG.
- **Grill the version scheme** before applying any tags — the right milestones are project-specific. Use Phase 1 to establish them.

## CHANGELOG Format

Use [Keep a Changelog](https://keepachangelog.com/) with `Added / Changed / Fixed` sections per version. Tips:

- **Lump** closely related commits under one bullet (e.g. "Param validation rolled out: forum topics, forum posts, communities routes")
- **Cite hashes** only for notable multi-commit eras (e.g. the v0.2.0 audit wave)
- **Alias** duplicate tags inline: `## [0.3.1] — date _(alias: v0.4.1)_`
- **Compare links** at bottom of file using `v{tag}...v{tag}` GitHub URL format

## Stub Tracking

Stubs worth tracking are routes/features that are:
- Live and working (frontend consuming them)
- But with incomplete response contracts or partial feature coverage
- NOT broken — just incomplete

Good candidates: a simple resource endpoint that returns bare `{}` instead of a meaningful response, a feature with no write path yet, a model with no routes at all.

File GitHub issues only with explicit user authorization. Save to memory otherwise.

**Note:** mr-janitor stub tracking is retrospective — it finds gaps in existing code. If you're starting a new feature, use [`/tdd`](https://github.com/mattpocock/skills/blob/main/skills/engineering/tdd/SKILL.md) instead; tests should come before implementation, not after.
