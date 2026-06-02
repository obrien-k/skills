# skills

A collection of Claude Code skills for AI-assisted development workflows, forked from [mattpocock/skills](https://github.com/mattpocock/skills).

## Installing a skill

Copy the skill directory into your Claude skills folder:

```bash
cp -r skills/engineering/mr-robot ~/.claude/skills/
```

Then invoke it in Claude Code with `/mr-robot` or by describing what you want to do.

## Engineering skills

- **[mr-robot](./skills/engineering/mr-robot/SKILL.md)** — Repo housekeeping SysOp: clean merged branches, apply version tags, sync forks, write CHANGELOG, track stubs. Pass `--plain` for no-emoji output.
