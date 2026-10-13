# Eval design: <agent or repository name>

<!-- Fill in within 10 to 15 minutes. Short sentences and tables. Replace every <...>; delete rows that do not apply. -->

## 1. Goal

- Decision this eval supports: <gate changes in CI / compare prompt or model versions / catch regressions before release>
- In scope: <call types>. Out of scope: <what, and why>
- Done means: <one command runs the suite, writes a report and returns a pass or fail gate>

## 2. Success conditions by call type

| Call type | Must happen | Must not happen | Evidence in the trace | Code or judge | Severity |
|---|---|---|---|---|---|
| <call type> | <outcome> | <forbidden action or phrase> | <tool call, argument, end state, turn> | <code / judge> | <critical / major / minor> |

## 3. Metrics

| Metric | Definition | Computed from | Gate |
|---|---|---|---|
| Task completion | calls with all critical and major checks passing / calls | check results | >= <x>; drop vs baseline <= <y> |
| Policy compliance | calls with zero critical violations / calls | check results | 100% |
| Transfer correctness | transferred vs expected, 2x2 table | transfer events | zero missed transfers |
| Field capture accuracy | captured value equals expected after normalization, per field type | write calls, end state | report only |
| Response latency p95 | caller speech end to agent audio start | event timestamps | <= <ms> (audio level only) |
| <judge criterion> | <one line> | calibrated judge | <gate if calibrated, else report only> |

## 4. Data

- Scenarios: <N> total; per call type: <...>; edge cases covered: <list>
- Callers: scripted <n>; simulated <n> x <k> runs, seed <...>
- Golden transcripts: <n>; known-bad variants: <n>
- Human labels for judge calibration: <N> items for <criteria>, labeled by <who>

## 5. Graders

- Deterministic: <tool calls and arguments, call order, fields, end state, transfer, forbidden phrases, read-back, end reason>
- Judge: criteria <...>; model <...>; rubric files <...>; structured output with reasoning before verdict
- Calibration: percent agreement, Cohen's kappa and fail recall on <N> labels; gating bar <kappa >= ..., fail recall >= ...>, set before measuring

## 6. Structure

- Runner level: <text / audio / offline logs>, because <what the repository exposes>
- Agent under test: <entry point>; stubs: <fake tools; LLM record-replay or scripted fake>
- Files: <paths>. Commands: <run>, <test>, <gate>
- Report: <report.md, report.json>; baseline: <file>; thresholds: <file>; CI: <where the gate runs>
- Reproducibility: <seeds, temperature where accepted, pinned model ids, cache>
- Cost: <turn and duration caps, judge calls per run, audio subset size>

## 7. Tradeoffs

- <Text level over audio level: fast and deterministic; cannot see turn-taking or real recognition errors>
- <Small hand-labeled set from one labeler: fast; wide uncertainty on agreement>
- <Small harness in the repository over framework X: no new dependency; less built-in tooling>

## 8. Next steps

- <Audio-level runs on a schedule; a second labeler; scenarios derived from production calls; more simulated personas>
