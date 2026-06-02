# skills

A collection of Claude Code skills for AI-assisted development workflows, forked from [mattpocock/skills](https://github.com/mattpocock/skills).

## Installing a skill

Copy the skill directory into your Claude skills folder:

```bash
cp -r skills/engineering/mr-robot ~/.claude/skills/
```

Then invoke it in Claude Code with `/mr-robot` or by describing what you want to do.

## Engineering skills

🎉🤖 **First official release — meet Mr. Robot.** Graduated off the in-progress bench into `engineering/`.

- **[mr-robot](./skills/engineering/mr-robot/SKILL.md)** — Repo housekeeping SysOp: clean merged branches, apply version tags, sync forks, write CHANGELOG, track stubs. Pass `--plain` for no-emoji output.

## Misc skills

- **[verbiagating](./skills/misc/verbiagating/SKILL.md)** — Fun/troll status strip above the input during long model waits. Escalates from cute to chaotic by elapsed time. Part of claudx-pi.
