# Skills Repo — Agent Guide

## Structure

Skills live under `skills/<bucket>/` where bucket is one of: `engineering`, `productivity`, `misc`, `personal`, `in-progress`, `deprecated`.

Every skill in `engineering/`, `productivity/`, or `misc/` **must** have:
- An entry in `.claude-plugin/plugin.json`
- A reference in the top-level `README.md` (skill name linked to its `SKILL.md`)
- An entry in the bucket's own `README.md`

Skills in `personal/`, `in-progress/`, or `deprecated/` must **not** appear in either README or `plugin.json`.

## Commits

- Develop on a feature branch, never commit directly to `main`
- Run format/lint/tests before committing if the repo has them (check `package.json` scripts, `Makefile`, `CLAUDE.md`)
- Never commit red
