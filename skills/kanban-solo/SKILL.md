---
name: kanban-solo
description: Plan and run one timed coding task as a single lane of tickets. Read the task and rubric, write a short brief with numbered requirements, a brief plan, tickets with acceptance criteria, then one ticket at a time with the test first and a check after each, then final-check and a separate submission turn. The plan files live outside the repository, in /tmp. Use for any build or fix task with more than one step in a single workspace. For a review without code changes, use pr-review (its fix mode hands each fix back to this loop).
---

# kanban-solo

One agent, one workspace, one lane: the parts of a team kanban that still pay off when nobody works in
parallel. The plan is a set of files outside the repository, so nothing about the process ends up in the
deliverable, and the user can see and steer it at any point.

## Files

All in `/tmp/kanban-solo/<repo-name>/`, where `<repo-name>` is the repository folder's name
(`mkdir -p` it first):

| File | Holds | Template |
| --- | --- | --- |
| `BRIEF.md` | The task in its own words: requirements R1, R2, ..., rubric lines C1, C2, ..., constraints, deliverables, the time box, open questions | `assets/BRIEF.md` |
| `PLAN.md` | The approach, the tickets in order with their status, the cut order, the risks | `assets/PLAN.md` |
| `LOG.md` | One line per event, stamped with `date`: start, decisions, ticket done, test results, cuts | none |

## Steps

1. **Clock.** Run `date` and write the time box into `BRIEF.md` (the user gives the time left; ask once if
   not). Budget: about 10% for intake and plan, at most 70% for the build, the rest for `final-check`, the
   submission turn and surprises.
2. **Intake, 5 to 10 minutes.** Read the problem statement, every requirement and rubric line, and the
   repository (README, entry points, tests). Run the existing tests once for a baseline. Write `BRIEF.md`:
   number every requirement and rubric line, keeping the task's own words, and list deliverables,
   constraints and open questions. Ask the user only what blocks the plan.
3. **Plan.** Write `PLAN.md`, then show the user a short version in chat (under 15 lines): the approach,
   the tickets with their tiers, the cut order, the main risk. Stop there and wait for the user's go: the
   user owns the decisions, and the plan is the cheapest moment to change course.
4. **Tickets.** Each ticket in `PLAN.md` has this shape:

   ```
   ## T1 · <title>   tier: mvp   status: todo
   - Serves: R1, R3 (C2)
   - Scope: <files and functions it touches>
   - Acceptance: <observable checks, each a test or a command with its expected result>
   - Test first: <the test that fails before the change and passes after>
   ```

   - **Order**: a walking skeleton first, the thinnest path through every layer end to end; later tickets
     add depth. An overrun then cuts polish, never the path that proves the deliverable works.
   - **Tiers**: `mvp` (required by the task), `signature` (one or two pieces worth showing: a design call,
     tests on the core logic), `stretch` (cut first).
   - **Size**: the mvp tickets fit within the 70% cap. If they do not, cut before starting and say what.
5. **The loop.** Do the tickets the user's message names (one, a range, or "the rest"), one at a time:
   1. Set the ticket's status to `doing` and log the start.
   2. Write the test from the acceptance checks. Run it and see it fail for the right reason.
   3. Implement until it passes. Run the ticket's tests and the tests around the code it touched; run the
      whole suite when it is fast.
   4. Check every acceptance item. Write down what is still fake, stubbed or missing as a known gap.
   5. Report in a few lines: the files changed, the commands run with their results, the known gaps, the
      next ticket.
   6. Set the status to `done` and log it.

   Keep a turn to about one ticket, so every successful turn saves a coherent, tested state.
6. **Re-plan when reality changes.** A ticket that takes one and a half times its size: stop, tell the
   user, propose the cut. New information (a requirement read differently, a broken dependency): update
   `BRIEF.md` or `PLAN.md` and log the decision with its reason.
7. **Freeze.** When the build budget is spent, start no new ticket. Finish or back out the current one so
   the tests pass.
8. **Close.** Run the `final-check` skill. The submission comes after it, in a turn of its own, when the
   user asks.

## Status on request

When the user asks where things stand: `date`, each ticket with its status, the time used and left, and
the next step, in under 10 lines. If the environment shows a plan or checklist (for example Codex's plan
updates), keep it in step with `PLAN.md`.
