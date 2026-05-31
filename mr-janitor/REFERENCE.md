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
- **Version scheme used in this project:**

| Range | Theme |
|---|---|
| v0.0.x | Scaffolding |
| v0.1.x | Domain model |
| v0.2.x | Validation + auth hardening |
| v0.3.x | Audit phases + test foundation |
| v0.3.9 | Feature wave complete |
| v0.4.x | Feature expansion + data gen |
| v0.5.x | Architecture deepening + test viability |

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

File GitHub issues only with explicit user authorization. Save to memory otherwise (`project_stubs.md`).

Known stubs in stellar-api (as of v0.5.3):
- **Friends** (#60) — `POST`/`PUT` return bare `{}`, one-directional add
- **Invite Tree** (#61) — route exists, frontend wiring unverified
- **Donations** (#62) — admin history view missing; donor perks implemented

## ADR Compliance Check

Always grep for ADR-0001 violations during stub pruning:

```bash
# Named role helper functions (not local variables — those are fine)
grep -rn "^const is[A-Z][a-zA-Z]* = async" src/routes --include="*.ts"
```

A `const isStaff = hasPermission(...)` local variable is fine.
A `const isStaffOrModerator = async (req, res) => ...` helper function is a violation.
