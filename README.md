# skills

A collection of Claude Code skills for AI-assisted development workflows, forked from [mattpocock/skills](https://github.com/mattpocock/skills).

## Installing a skill

Copy the skill directory into your Claude skills folder:

```bash
cp -r skills/engineering/mr-janitor ~/.claude/skills/
```

Then invoke it in Claude Code with `/mr-janitor` or by describing what you want to do.

## Engineering skills

- **[mr-janitor](./skills/in-progress/mr-janitor/SKILL.md)** — Repo housekeeping: clean merged branches, apply version tags, sync forks, write CHANGELOG, track stubs. Pass `--plain` for no-emoji output.
