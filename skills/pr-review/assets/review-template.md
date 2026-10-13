# Review: <PR title>

<!-- Fill every section, replace each <placeholder>, and remove this comment. Keep findings in severity order. -->

- PR: <URL, number, or branch name>
- Base: `<branch>` at `<sha>`
- Head: `<branch>` at `<sha>`
- Mode: <review only | review and fixes>

## Summary

<Two to four sentences in your own words: what the PR changes, how a warm transfer now works end to end, and the main risk.>

## Verdict

<Approve | Approve with suggestions | Request changes>: <one sentence with the reason>.

| Severity | Findings | Must-fix |
| --- | --- | --- |
| Critical | <n> | <n> |
| High | <n> | <n> |
| Medium | <n> | <n> |
| Low | <n> | <n> |

## Tests run

| Revision | Command | Result |
| --- | --- | --- |
| Base `<sha>` | `<exact command>` | <passed, failed, skipped; exit code> |
| PR `<sha>` | `<exact command>` | <passed, failed, skipped; exit code> |
| After fixes | `<exact command>` | <passed, failed, skipped; exit code> |

<List failures that also occur on base as pre-existing. For anything that could not run, say what blocked it.>

## Findings

### Critical

#### F1. <What breaks, in a few words>

- Label: must-fix
- Location: `<path/to/file.ext:line>`
- Scenario: <inputs or event sequence>, then <the wrong outcome for the caller, the human, or the operator>.
- Cause: <the code fact, with the one or two lines that show it>.
- Fix: <the concrete change>.
- Test: <the test that fails today and passes after the fix>.
- Fixed (fix mode only): <files changed>; `<test name>` failed before the fix and passes after it.

### High

### Medium

### Low

## Questions for the author

- Q1. <What could not be confirmed, where you looked, and which answer would turn it into a finding.>

## Requirements

| ID | Requirement | Status | Evidence |
| --- | --- | --- | --- |
| R1 | <from the problem statement or linked issue> | <Met, Partly met, Not met, or Not verifiable> | `<file:line>` or `<test name>` |

## Not reviewed

- <Files, paths, or environments not covered, and why.>

---

## PR comment format

When the task asks for PR comments, write one block per finding for the user to post. Do not post them.

```
<path/to/file.ext:line>
[F1, must-fix, High] <What breaks>
Scenario: <event sequence>, then <wrong outcome>.
Suggested fix: <change>.
Test: <test name or what it checks>.
```
