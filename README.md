# skills

A collection of Claude Code skills for AI-assisted development workflows.

## Installing a skill

Copy the skill directory into your Claude skills folder:

```bash
cp -r mr-janitor ~/.claude/skills/
```

Then invoke it in Claude Code with `/mr-janitor` or by describing what you want to do.

## Skills

### [mr-janitor](./mr-janitor/)

Repo housekeeping — cleans merged branches, applies retroactive version tags, syncs forks, writes CHANGELOG.md, and files stub tracking issues. Grills you on strategy before touching anything. 🧹😈🤘

**Invoke:** `/mr-janitor` · "janitor mode" · "sweep the repo" · "clean up branches"
