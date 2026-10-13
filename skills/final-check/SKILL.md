---
name: final-check
description: The last pass before submitting a timed coding task. Check every requirement and rubric line against concrete evidence (file and line, test name, command output), fix the gaps that fit the time left, run the tests, review the diff for anything that does not belong, write the submission summary and pull request text, then stop so the user can ask for the submission in a separate turn. Use when the build or review is done, when the time is nearly up, or when the user asks to check the work against the requirements.
---

# final-check

The requirements decide what "done" means, not the plan: plans drop words. This pass rereads the original
task, proves each line with evidence, and leaves the workspace in a state that is safe to submit.

## Steps

1. **Clock.** Run `date` and note the time left. If less than 10 minutes remain, do steps 2, 3, 4 and 8
   only, and list the rest as known limitations.
2. **The list.** Take every requirement and rubric line from the original task statement. `BRIEF.md` in
   `/tmp/kanban-solo/<repo-name>/` has them numbered; reread the original anyway.
3. **Evidence, line by line.** For each line, find the proof in the repository as it is now: the file and
   line that implement it, the test that shows it, or a command and its output. Fill in the matrix
   (template in `assets/matrix.md`):

   | ID | Requirement (task's words) | Evidence | Status |
   | --- | --- | --- | --- |
   | R1 | ... | `src/eval/report.py:42`, `test_report.py::test_regression_flag` | met |

   Status is one of `met`, `partial`, `missing`, `not applicable` (with the reason). A line whose evidence
   is only "the code looks right" is `partial` until a test or a run shows it.
4. **Run the checks.** The relevant test suite, plus the build, type check or lint the repository already
   uses. Record the exact commands and the counts. A failure is fixed or explained, never skipped. A test
   that already failed in the baseline run (`BRIEF.md`) is pre-existing: report it as such, and change code
   outside the task's scope to fix it only when the task asks for it or the user says so.
5. **Review the diff.** `git status --porcelain --untracked-files=all`, `git diff --stat`, then the diff
   itself. Remove what does not belong in the deliverable: scratch files, logs, caches, `.env` files,
   large generated data, debug prints, commented-out code, unrelated reformatting, notes to yourself.
   Nothing secret, nothing personal.
6. **Close the gaps that fit.** Fix `partial` and `missing` lines in order of value per minute, running
   the tests after each fix. A gap that needs more than a small change (a new component, or more than
   about ten minutes) is the user's call: list it with its estimate and ask before building it. What does
   not fit becomes a known limitation, said plainly.
7. **Docs.** When the task asks for documentation or the repository has a README for this area: how to
   run it, how to run its tests, what was built, the main tradeoffs, the known limitations, the next steps.
8. **Summary and pull request text** (template in `assets/summary.md`): what was delivered, one line per
   requirement with its evidence, the tests run and their results, known limitations, next steps; a pull
   request title under 70 characters and a short description.
9. **Stop.** Tell the user the work is ready to submit and that the submission should be its own turn.
   Do not call a submission tool in this turn.

## The submission turn

When the user asks to submit: confirm that the last file-changing turn finished and its tests passed,
call the environment's submission tool for the latest saved revision with the summary from step 8, and
report its answer word for word. Change no files in this turn.
