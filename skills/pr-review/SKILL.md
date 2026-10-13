---
name: pr-review
description: Review a pull request (PR review, code review) of a voice agent, especially one that migrates the agent to a new voice or telephony platform or adds warm transfer or call transfer to a human. Use when asked to review, critique, or fix an existing PR, branch, or diff. Produces findings ordered by severity, each with file:line, a concrete failure scenario, a suggested fix, and a must-fix or suggestion label, delivered as a review file or as comment text; in fix mode it also fixes the must-fix findings test-first. The process fits any PR; the telephony checklists apply when the diff touches calls, webhooks, conferences or rooms, hold audio, or handoff summaries. Do not use it to build a feature from a spec when there is no PR, and never to push or to post to GitHub.
---

# PR review: voice platform migration and warm transfer

Input: a repository checkout, the problem statement, and the PR (a local branch, a diff, a description file, or a public GitHub URL).
Output: a written review with findings ordered by severity and the exact test commands you ran with their results; in fix mode, also the fixed code with one new test per fix.

Files in this skill:

- `references/migration-checklist.md`: what to check when a voice agent moves between platforms.
- `references/warm-transfer-checklist.md`: the transfer state machine, failure paths, races, cleanup, and what the human receives.
- `references/platforms.md`: how Twilio, LiveKit, Pipecat, Vapi, and Retell build warm transfer, the events involved, and known pitfalls.
- `assets/review-template.md`: the written review and the PR comment format.
- `assets/finding.example.md`: one complete finding to copy the shape from.

Session rules come from `working-rules`. In fix mode each must-fix finding is one `kanban-solo` ticket. Run `final-check` before calling the work done.

## 1. Choose the delivery mode

Read the problem statement before anything else and pick one mode.

- Review mode: the deliverable is the review. Signals: "review this PR", "leave comments", "write up the issues", "what would you change". Do not edit source files.
- Fix mode: the deliverable is a corrected branch. Signals: "fix", "make it production ready", "address the problems", "get the tests passing".

If the statement does not settle it, ask the user one question and wait for the answer: "Should I deliver a written review only, or also fix the must-fix findings on this branch?" Write the chosen mode as the first line of your notes.

## 2. Get the PR content without changing anything

Keep notes and scratch files in `/tmp/kanban-solo/<repo-name>/`, never in the repository.

Look at the repository first:

```
git status --short
git remote -v
git branch -a
git log --oneline --graph --all -20
```

Then find the base and the head:

- Two local branches: `git merge-base <base> <head>`, `git log --oneline <base>..<head>`, `git diff --stat <base>...<head>`, then `git diff <base>...<head> -- <path>` one file at a time. The three-dot form diffs against the merge base, so it shows only the PR's own changes.
- Uncommitted work only: `git diff`, `git diff --staged`, and the untracked files listed by `git status --short`.
- A PR description: look for `PR.md`, `PULL_REQUEST.md`, `.github/pull_request_template.md`, `docs/`, or text in the problem statement.
- A public GitHub PR, read without credentials: `curl -sL https://github.com/<owner>/<repo>/pull/<n>.diff` returns the diff; `curl -s https://api.github.com/repos/<owner>/<repo>/pulls/<n>` returns the title, body, base, and head; append `/files` or `/comments` for the file list and review comments. With a GitHub remote and a writable `.git`, `git fetch origin pull/<n>/head:pr-<n>` creates a local branch for the PR head; in a sandbox, where `.git` is read-only, use the `.diff` URL. Unauthenticated API calls are limited to 60 per hour, so fetch each URL once and save the output in the notes folder.

Never run `git push`, never log in to GitHub or configure a token, and never post comments or reviews (`gh pr comment`, `gh pr review`, API writes). If the task says "comment on the PR", produce the comment text for the user to post.

Write the base SHA and the head SHA at the top of the notes.

## 3. Read intent before code

Read in this order and write one line per item in the notes:

1. The PR description: every claim the author makes ("the caller returns to the AI when the human declines").
2. The linked requirements: issue, spec, problem statement, rubric. Number them R1, R2, and so on.
3. The tests in the PR: what each one proves, and which paths have no test.
4. Configuration and deployment changes: environment variables, flags, webhook routes.
5. The diff, file by file.

The claims and requirements are the list you verify. A claim with no code or test behind it becomes a finding or a question.

## 4. Run the tests on base and on the PR

1. Find the test command in the README, `package.json` scripts, `Makefile`, `pyproject.toml`, or the CI config.
2. Leave the working tree as you found it: the environment saves it as the deliverable, and in a sandboxed session `.git` is read-only, so `git checkout` and `git worktree add` fail. Export each revision to the notes folder and run the suite there:

   ```
   mkdir -p /tmp/kanban-solo/<repo-name>/base /tmp/kanban-solo/<repo-name>/head
   git archive <base-sha> | tar -x -C /tmp/kanban-solo/<repo-name>/base
   git archive <head-sha> | tar -x -C /tmp/kanban-solo/<repo-name>/head
   ```

   When the checked-out tree is the PR head, run the head's suite in place instead. If the PR changes dependency files, install dependencies for each copy before its run (ask the user before any download).
3. Record each exact command, its exit code, and the pass, fail, and skip counts. A test that also fails on base is pre-existing; report it separately.
4. If the suite cannot run (a missing service or secret), write down what blocked it. Never report a result you did not see.

## 5. Review the diff

1. Group the changed files: platform adapter or client, webhook handlers, call and transfer state, prompts and summaries, configuration, tests.
2. Walk `references/migration-checklist.md` over the adapter, webhook, and configuration groups.
3. Walk `references/warm-transfer-checklist.md` over the state and transfer groups.
4. Compare the transfer flow with the platform's section in `references/platforms.md`: the primitives used, the events the code must handle, the pitfalls listed. For a platform not covered there, read its official docs for the same three things.
5. Trace these paths through the code, function by function, and note the line where each could go wrong:
   - a normal call on the new platform, from first ring to hang-up;
   - a warm transfer that succeeds;
   - a transfer where the human does not answer;
   - the caller hanging up while on hold;
   - one webhook delivered twice, and two webhooks arriving in reverse order.
6. Confirm each suspected problem: read the code it calls, check the platform docs, or run a small script or test. In review mode, keep such scripts in the notes folder.

A problem you cannot confirm goes under "Questions for the author", not under findings.

## 6. Write findings

Every finding has these fields (see `assets/finding.example.md`):

- **Title**: what breaks, in a few words.
- **Severity**: Critical, High, Medium, or Low (the P0 to P3 priorities of Codex's built-in `review-agent` skill).
- **Label**: must-fix or suggestion.
- **Location**: `path/to/file.ext:line` for each place that has to change.
- **Scenario**: the inputs or the event sequence, then the wrong outcome that the caller, the human, or the operator sees.
- **Cause**: the code fact behind it, with the one or two lines that show it.
- **Fix**: the concrete change.
- **Test**: the test that fails today and passes after the fix.

Severity:

- Critical: a common path fails, or data leaks. Calls drop, a caller waits on hold with nobody coming, an unauthenticated request can start or end a transfer, PII reaches someone who should not have it.
- High: a realistic failure path breaks (no answer, busy, voicemail, caller hang-up during the transfer, a duplicate or late webhook), rollback does not work, or a stated requirement is not met.
- Medium: degraded behavior, a missing test for a failure path, logs or metrics too thin to debug a failed transfer.
- Low: naming, structure, small cleanups.

Critical and High are must-fix; Medium and Low are suggestions. Order findings by severity, then by how often the triggering path happens in production.

## 7a. Deliver in review mode

Fill `assets/review-template.md`.

- If the problem statement names a file, write the review there. Otherwise write `REVIEW.md` at the repository root and say so: when the submission carries the repository's files, a review kept only in the chat or in `/tmp` leaves nothing to submit. If the task rules out new files, ask the user where the review goes.
- If it asks for PR comments, give one paste-ready block per finding, headed by `path:line`, in the comment format from the template.
- Change nothing else in the repository.

## 7b. Deliver in fix mode

1. Write the full findings list first (step 6), so the user sees what will and will not be fixed.
2. Make each must-fix finding one `kanban-solo` ticket, highest severity first.
3. For each ticket:
   1. Write a test that reproduces the finding's scenario.
   2. Run it and see it fail for the reason the finding states. A test that passes before the fix proves nothing; rewrite it.
   3. Make the smallest change that fixes the scenario and keeps the PR's intent. Never revert the migration, remove warm transfer, or delete a feature to make a test pass.
   4. Run the new test and the full suite. Record the commands and results.
4. Leave suggestions unfixed unless the user asks; list them in the review.
5. Under each fixed finding in the review, add the files changed, the test name, and the result before and after.
6. Keep the diff to the PR plus the fixes: no unrelated refactors, no formatting sweeps.

## 8. Hand off

Report the mode, the verdict, the number of findings per severity, the test commands with results (base, PR, and after fixes), the open questions, and what you did not review. Then run `final-check`. Submission happens only when the user asks for it, in a later turn.

## Review honestly

- No line and no scenario means no finding.
- A finding is introduced by this PR. Problems that predate it go in a short "Pre-existing" note, not in the findings.
- Mark guesses as questions, and quote the code you relied on.
- Do not label style preferences as must-fix.
- Name the files and paths you did not cover.
- If the PR is sound, say so. An empty must-fix list is a valid result.

## Time plan for about 50 minutes

| Minutes | Review mode | Minutes | Fix mode |
| --- | --- | --- | --- |
| 0-5 | Mode, PR content, description, requirements | 0-5 | Same |
| 5-10 | Tests on base and PR; read the tests | 5-10 | Same |
| 10-35 | Checklists and path traces | 10-22 | Checklists and path traces |
| 35-45 | Findings and questions | 22-27 | Findings list |
| | | 27-45 | One ticket per must-fix finding |
| 45-50 | Summary, then `final-check` | 45-50 | Summary, then `final-check` |

If time runs short in fix mode, stop after the last finished ticket and list the unfixed must-fix findings in the summary.
