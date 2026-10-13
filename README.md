# e3-coding-toolkit

v0.1.0

Codex skills I prepared for a timed, AI-assisted coding round that runs in one hosted Codex workspace. Two
are domain playbooks: designing and building an evaluation system for a voice agent, and reviewing a pull
request that moves a voice agent to a new telephony platform and adds warm transfer. Three carry the way I
work: the session's rules, a single-lane ticket loop, and a final check of every requirement before
submitting.

## Install

In the Codex session, before starting the task:

> Before we start, install my toolkit. Clone https://github.com/Anchor-ZhuoHU/e3-coding-toolkit into
> /tmp/e3-coding-toolkit, outside this repository (if that folder already exists, run git pull in it instead),
> then run /tmp/e3-coding-toolkit/install.sh. If the sandbox blocks a step, request approval to run that step
> outside the sandbox; if approval is not possible, stop and tell me exactly what is missing. Then read the
> toolkit's working-rules skill and follow it for the rest of this session.

Or in a shell:

```bash
git clone --depth 1 https://github.com/Anchor-ZhuoHU/e3-coding-toolkit /tmp/e3-coding-toolkit
/tmp/e3-coding-toolkit/install.sh              # --dry-run to preview, --uninstall to undo
```

The installer takes about a second and can run again at any time (it refreshes the earlier install):

- It copies the skills to `~/.agents/skills`, where Codex looks for user skills and picks up new ones
  without a restart.
- It appends the short rules in [`config/AGENTS.md`](config/AGENTS.md), between two marker lines, to the
  global instructions file in the Codex home (`AGENTS.md`, or `AGENTS.override.md` when that one is in use).
  The file's existing content stays byte for byte, and `--uninstall` takes the block back out.
- It never touches `config.toml`, writes nothing inside a git repository (it refuses when a target is inside
  one), and checks every target before changing anything: a folder it cannot write to stops it with a clear
  message and nothing changed.

Options: `--skills-dir DIR`, `--codex-home DIR`, `--no-rules`. Details: `./install.sh --help`.

## Skills

| Skill | Use it for |
| --- | --- |
| [`working-rules`](skills/working-rules/SKILL.md) | The session's rules: read before editing, plan first, one piece at a time with tests, no pushes or credentials, nothing unrelated in the repository, submission in a turn of its own |
| [`kanban-solo`](skills/kanban-solo/SKILL.md) | Any build or fix task with more than one step: a brief with numbered requirements, a plan, then tickets one at a time, each with its test first; the plan files live in `/tmp`, outside the repository |
| [`agent-eval-system`](skills/agent-eval-system/SKILL.md) | Designing and building an evaluation system for a voice agent: from requirements to an eval spec, scenarios and edge cases, deterministic graders and a calibrated LLM judge, voice metrics, the report and a CI gate |
| [`pr-review`](skills/pr-review/SKILL.md) | Reviewing a pull request, with checklists for platform migrations and warm transfer, and notes on how common voice platforms implement warm transfer; review only, or fix with tests |
| [`final-check`](skills/final-check/SKILL.md) | The last pass: every requirement and rubric line checked against evidence, the diff cleaned, the tests run, the submission summary written; the submission itself comes in the next turn |

Name a skill in the prompt to use it, for example "Use the pr-review skill to review the pull request on
branch feature/x".

## How they fit

```
install ─▶ working-rules ─▶ kanban-solo: brief ─▶ plan (the user's go) ─▶ tickets ─▶ final-check ─▶ submit
                               │                                             ▲
                               ├── agent-eval-system shapes the plan and the tickets
                               └── pr-review in fix mode turns each must-fix finding into a ticket
```

## Design notes

- **The rules are a skill as well as an AGENTS.md block.** Codex reads its global instructions when a
  session starts, so a block added mid-session applies from the next session on. The install prompt asks
  Codex to read the `working-rules` skill right away instead.
- **Nothing lands in the repository being worked on.** The toolkit is cloned to `/tmp`, the skills go to the
  home folder, and the plan files go to `/tmp/kanban-solo/<repo-name>/`, so the pull request holds only the
  work.
- **No MCP server and no `config.toml` changes.** A hosted workspace keeps its own tools in that file. The
  skills need nothing beyond a shell; diagrams are Mermaid, which GitHub renders in the pull request.
- **Narrow on purpose.** General workflow libraries for coding agents exist (for example
  [obra/superpowers](https://github.com/obra/superpowers)). These skills encode the constraints of a recorded
  single-workspace session instead: no pushes, one agent, a separate submission turn, and plan files outside
  the repository.

## Tests

`scripts/test-install.sh` runs the installer in a throwaway home whose Codex folder already has its own
`config.toml` and `AGENTS.md`, from inside a small git repository. It checks that a second run gives the same
result, that the existing files keep every byte, that the repository gains no file, that the uninstall
restores everything exactly, and that a home inside a repository or a folder it cannot write to is refused
with nothing changed.

## License

MIT, see [LICENSE](LICENSE).
