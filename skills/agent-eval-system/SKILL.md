---
name: agent-eval-system
description: Evaluation system, evals and test harness for a voice agent or phone agent (speech recognition, an LLM with tools, text to speech), built inside an existing repository in about 90 minutes. Use when a task asks to design or implement evals, scoring, an LLM-as-judge, a regression report or a CI quality gate for a conversational agent that handles calls. Covers per-call-type success criteria, scenario datasets with voice edge cases (misheard numbers, IDs and names, barge-in, silence, out-of-scope requests, requests for a human, policy violations), deterministic graders, a judge calibrated against human labels (percent agreement and Cohen's kappa), voice metrics (response latency, interruption handling, turn-taking, task completion, containment, hallucination, policy compliance), reproducibility and cost control. Do not use it to build or fix the agent itself, to benchmark a base model on public datasets, or to load-test telephony infrastructure.
---

# Agent eval system

Build an evaluation system for a voice agent inside the repository you were given: a dataset of call scenarios, a runner that drives the agent, graders, an aggregated report, and a gate that CI can run. Reviewers read the whole session afterwards, so each step leaves evidence: a stated plan, a design document, tests that fail before they pass, and a report with real numbers.

Process comes from the sibling skills. Follow `working-rules` for the session's hard rules, run the build as tickets through `kanban-solo` (its plan files live in `/tmp/kanban-solo/<repo-name>/`, never in the repository), and run `final-check` before calling the work done. This skill supplies what goes into the plan and the tickets.

## Inputs and outputs

Inputs: the problem statement, the rubric if one is given, the repository.

Outputs, inside the repository and in its language, layout and test runner:

- the design document, filled in from `assets/design-doc.md` (for example `evals/DESIGN.md`)
- scenario files, golden transcripts and known-bad variants of them
- a runner, deterministic graders, an LLM judge, metric functions, a report generator and a gate command
- unit tests for every grader and metric function
- a report from a real run, a baseline file and a thresholds file
- a short `evals/README.md`: how to run it, what each metric means, what it does not measure

Nothing unrelated goes into the repository: it becomes a public pull request. Plans, scratch output and caches you do not mean to ship go to `/tmp`. Never `git push`; submission happens in a separate turn, when the user asks for it.

## Time plan

| Minutes | Steps | Done when |
|---|---|---|
| 0-10 | 1. Read problem, rubric, repository | requirements and repository facts written in `BRIEF.md` |
| 10-25 | 2-3. Eval spec, design document, plan | design document saved, plan stated to the user, tickets created |
| 25-45 | 4. Walking skeleton | one scenario runs end to end through runner, one grader, report |
| 45-65 | 5. Breadth | every call type and every named edge case has a scenario; graders and metrics tested |
| 65-80 | 6. LLM judge and calibration | agreement and kappa printed in the report |
| 80-90 | 7-8. Gate, README, final check | gate exits nonzero on a known regression and zero on the baseline |

When behind schedule, cut in this order: audio-level runs, simulated callers, judge criteria beyond two, scenario count. Keep grader tests, the report and the gate.

## Step 1. Read before designing

Input: problem statement, rubric, repository.

1. Read the problem statement and the rubric. Copy every requirement and rubric line into kanban-solo's `BRIEF.md`, numbered R1, R2, ... and C1, C2, ...; `final-check` checks them at the end.
2. Map the repository. Find and note with file paths:
   - language, package manager, test runner and the exact test command (run the existing tests once)
   - the agent entry point: where a caller utterance goes in and agent text plus tool calls come out
   - tool definitions and their argument schemas; which tools write state, transfer or end the call
   - the system prompt and any policy text
   - existing mocks, fixtures, recorded calls, logs, eval code and CI configuration
   - whether the agent can run without network, and where the LLM client and the tools could be swapped for fakes
3. Useful commands: `git ls-files`, `rg -n "tool|function|transfer|end_call|hangup"` (or `grep -rn -E` where `rg` is missing) (or `grep -rnE`), reading `pyproject.toml` or `package.json`, the CI workflow files.

Output: a "Repository facts" section in `BRIEF.md`. If a requirement is ambiguous and the answer changes the design, ask the user once and state the default you will use if there is no answer.

## Step 2. Turn requirements into an eval spec

Input: requirements checklist, repo facts.

1. List the call types (each distinct job the agent does; inbound and outbound calls are separate types).
2. For each call type, write its success conditions as rows: what must happen, what must not happen, the evidence in the trace that proves it, whether code or a judge decides it, and a severity (critical, major, minor).
3. Only then choose metrics: each metric aggregates check results or measurements from the trace.

Output: the spec table. Method and examples: `references/spec-and-dataset.md` (sections 1 and 2) and `references/metrics.md`.

## Step 3. Write the design document and state the plan

Input: spec table, repo facts.

1. Choose the runner level from what the repository exposes: text level, audio level or offline logs (`references/architecture.md`, section 3).
2. Decide reuse or build (`references/frameworks.md`). Default to a small harness inside the repository. Adopt a framework when the repository already uses one or the problem asks for it.
3. Write the tickets into kanban-solo's `PLAN.md` in the order of steps 4 to 8, with the design document as the first ticket.
4. Before editing any repository file, tell the user the plan in a few lines: runner level, call types, graders, judge criteria, gate rules, what is out of scope, the tickets. Then stop and wait for the user's go (kanban-solo, step 3).
5. After the go, copy `assets/design-doc.md` into the repository and fill it in within 10 to 15 minutes.

Output: design document, stated plan, tickets.

## Step 4. Walking skeleton

Input: design document. One ticket per item, each verified before the next.

1. Trace schema and an adapter from the agent's real outputs to it (`references/architecture.md`, section 2; event types in `references/metrics.md`, section 1).
2. One scenario for the most important call type, in the schema shown in `assets/scenario.example.yaml`.
3. The runner for that scenario with a scripted caller. If the agent cannot run offline, stub the LLM and the tools deterministically (`references/architecture.md`, section 4).
4. One deterministic grader, test first: tests against a golden trace and a known-bad variant; run them and show the failure; implement; run again and show the pass (`references/graders.md`, section 5).
5. The report: per-scenario pass or fail with evidence, per-metric value with N.

Output: one command that goes scenario, trace, grader, report.

## Step 5. Breadth

Input: the skeleton.

1. Add scenarios until each call type has a happy path and each edge case named by the problem has a case. Catalog: `references/spec-and-dataset.md`, section 5.
2. Add deterministic graders, each test first (`references/graders.md`, sections 2 and 5).
3. Add metric functions computed from the trace (`references/metrics.md`), with unit tests on small hand-built event logs.
4. Check that every critical success condition can fail: some scenario or known-bad trace makes its check fail.

Output: dataset, graders and metrics; the report shows every metric, or marks it "not measured" with the reason.

## Step 6. LLM judge and calibration

Input: the success conditions that code cannot decide (tone, whether explanations are grounded in tool results, whether a refusal offered an allowed alternative).

1. Write one rubric per criterion from `assets/judge-rubric.md`: pass and fail definitions, hard cases, two to four labeled examples, structured output with reasoning before the verdict.
2. Get a calibration set labeled by a person, normally the user, before running the judge: 20 to 40 items, both labels present, few-shot examples kept out of it. If nobody can label in time, use items whose label is fixed by construction (goldens and known-bad variants) and say so in the report.
3. Run the judge on the set; compute percent agreement, Cohen's kappa and recall on failures; read every disagreement.
4. Revise the rubric at most once, freeze it, measure again. Decide per criterion: gate on it, report it only, or drop it.
5. Unit-test the judge plumbing with a fake client (parsing, malformed output, caching).

Output: judge module, labels file, a calibration section in the report. Detail: `references/graders.md`, sections 3 and 4.

## Step 7. Report, baseline and gate

Input: graders, judge and metrics.

1. Run the full suite. Save the summary as the baseline.
2. Write the thresholds: critical checks at 100 percent, task completion and latency budgets from the spec, a maximum drop against the baseline, and judge criteria only where calibration met the bar written in the design document.
3. Make the gate command exit nonzero when a rule fails and list the failing rules.
4. Prove the gate: make one scenario expectation wrong (or point the gate at a stored run with a known regression), run the gate and show it failing, restore, show it passing. Changing what the agent sees would only produce a replay cache miss.
5. Add the gate to the repository's CI configuration if one exists, with LLM calls in replay mode; keep live-model and audio runs out of the default CI path.

Output: report (Markdown and JSON), baseline, thresholds, gate command, CI step. Detail: `references/architecture.md`, sections 5 to 8.

## Step 8. Hand-off

Input: the finished harness and its report.

1. Write `evals/README.md`: commands, a glossary of metrics with their definitions, what is not measured at this runner level, next steps.
2. Run the repository's tests, the grader tests and the gate once more.
3. Run `final-check` against the requirement checklist from step 1.

Output: README, a final passing run of tests and gate, the final-check result.

## Decision rules

- Code decides whatever the trace or the end state can prove. The judge handles only the rest.
- Grade outcomes, not wording: tool calls, arguments, captured fields, end state. Never assert the agent's exact sentences.
- A transcript that reads well can still hide a wrong booking. Pair every judged action with a state check.
- Report only what the runner level can see. A text-level run marks voice-to-voice latency and turn-taking "not measured", never zero.
- Live models and simulated callers vary between runs: repeat those scenarios and report pass^k (`references/metrics.md`, section 2).
- Show counts next to rates when N is small: `7/9 (78%)`.
- Judge criteria enter the gate only after calibration meets the bar written down before the numbers were seen.
- Write the eval in the repository's language and test runner; snippets in this skill are illustrations, not code to paste.

## Files in this skill

- `references/spec-and-dataset.md`: requirements to eval spec, scenario schema, golden transcripts, voice edge cases
- `references/graders.md`: deterministic graders, LLM judge, calibration and agreement statistics, grader unit tests
- `references/metrics.md`: event log, task and voice metrics, how to compute each from a trace
- `references/architecture.md`: components, interfaces, text versus audio level, offline stubs, report, gate, reproducibility, cost
- `references/frameworks.md`: reuse or build, and the verified list of evaluation frameworks and voice testing tools
- `assets/design-doc.md`: the 10 to 15 minute design document template
- `assets/scenario.example.yaml`: one complete scenario in this skill's schema
- `assets/judge-rubric.md`: judge prompt template and structured output schema
