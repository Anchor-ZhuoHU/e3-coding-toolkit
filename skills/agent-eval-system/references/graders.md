# Graders

## 1. Interface

A grader is a pure function from one trace and its scenario to a list of check results. No network, no wall clock, no randomness: the same trace always gets the same grade, and old traces can be re-graded.

```python
@dataclass
class CheckResult:
    check_id: str     # "tool_args.reschedule_appointment"
    status: str       # "pass" | "fail" | "not_applicable" | "error"
    severity: str     # "critical" | "major" | "minor"
    evidence: str     # turn index, tool call id, or the offending text
    detail: str = ""

Grader = Callable[[Trace, Scenario], list[CheckResult]]
```

`error` means the grader could not decide (for example, the judge returned malformed output). It never counts as a pass, and the report lists it.

## 2. Deterministic graders

Write these first; most success conditions need nothing else.

| Grader | Passes when | Notes |
|---|---|---|
| `tool_called(name, args)` | a call with that name exists and each listed argument matches after normalization | extra arguments are ignored (the same subset rule Pipecat Evals uses) |
| `tool_not_called(name)` | no call with that name | forbidden and out-of-scope actions |
| `call_order(a, b)` | the first call to `a` comes before the first call to `b` | verification before lookup |
| `fields_captured(fields)` | the write call or the end state holds each required field with the expected normalized value | per-field results feed field capture accuracy |
| `end_state(expected)` | the fake tools' state after the call contains the expected subset | strongest check for actions (tau-bench grades the final database state) |
| `transfer(expected, within_turns)` | a transfer happened if and only if expected, in time | emits the cell of the transfer table |
| `forbidden_phrases(patterns)` | no agent turn matches any pattern | regexes; include internal tool names and prompt fragments |
| `readback(field)` | an agent turn before the write contains the normalized value | catches misheard values accepted silently |
| `no_claim_after_error(tool)` | after an error from that tool, no agent turn states its result | hallucination guard |
| `end_reason(expected)` | the call ended for the expected reason | completed, voicemail, idle timeout, transfer |
| `latency_budget(ms)` | every measured response latency is within budget | `not_applicable` when the runner has no timestamps |

Put normalization in one module with its own tests: phone numbers to digits, dates and times to ISO 8601, names case-folded with collapsed whitespace, spoken digits ("five five five") to numerals where the agent passes caller text through. Most false failures come from normalization, not from the agent.

```python
def tool_called(name: str, args: dict, severity="critical") -> Grader:
    def grade(trace: Trace, scenario: Scenario) -> list[CheckResult]:
        calls = [e for e in trace.events if e.type == "tool_call" and e.data["name"] == name]
        for call in calls:
            if all(norm(k, call.data["args"].get(k)) == norm(k, v) for k, v in args.items()):
                return [CheckResult(f"tool_args.{name}", "pass", severity, call.data["id"])]
        seen = [c.data["args"] for c in calls] or "no call"
        return [CheckResult(f"tool_args.{name}", "fail", severity, str(seen))]
    return grade
```

## 3. LLM-as-judge, only where code cannot decide

Judge criteria that need reading comprehension: whether an explanation is supported by the tool results, whether a refusal offered an allowed alternative, whether the agent answered the content of an interruption, tone and brevity. Everything that a tool call, an argument, the end state or a regex can prove stays in code.

- **One criterion per call, binary verdict.** `pass`, `fail` or `not_applicable`. Binary verdicts are easier to label and calibrate than 1 to 10 scales; the OpenAI evaluation guide recommends pass/fail or pairwise comparison for reliability.
- **Explicit rubric.** The criterion in one sentence, what counts as pass, what counts as fail, the hard cases, and two to four short labeled examples with at least one pass and one fail. Template: `assets/judge-rubric.md`.
- **Inputs.** The transcript with turn numbers and the tool calls and results inline (grounding cannot be judged without the results), the scenario goal and expected outcome, and the policy excerpt that matters. Not the whole system prompt.
- **Structured output.** JSON with the reasoning before the verdict: `criterion`, `reasoning`, `verdict`, `evidence_turns`. Enforce the schema with the provider's structured output feature where it exists; otherwise parse, validate, retry once, and record `error`.
- **Bias control.** LLM judges show position, verbosity and self-enhancement biases (Zheng et al., 2023). Grade one transcript against a rubric rather than comparing two; when comparing two, run both orders. State in the rubric that length is not a merit. Use a judge from a different model family than the agent when one is available.
- **Determinism and cost.** Temperature 0 where the API accepts it (some reasoning models do not support temperature while reasoning is on), a pinned model version, and a response cache keyed by a hash of model, prompt, schema and transcript.

## 4. Calibration against human labels

A judge is another model with its own errors, so measure them before trusting its verdicts.

1. **Build the set.** 20 to 40 (transcript, criterion) items. Mix real runs, golden transcripts and known-bad variants so both labels occur, and include borderline cases. Few-shot examples in the rubric must not appear in this set.
2. **Get human labels first.** Labels come from a person, not from a model; a model labeling the set would calibrate one model against another. Write the items to a labeling file (`labels/<criterion>.jsonl`: `item_id`, transcript excerpt with turn numbers, criterion, empty `label` and `note`). Ask the user once whether they will label the set now, before any judge verdict exists (20 items take a few minutes), or whether to use constructed labels; under a tight clock, constructed labels are the default. Constructed labels come only from items whose label is fixed by construction (goldens pass, the known-bad variant aimed at the criterion fails), and the report says these labels were constructed, not independently judged. List an independent labeler under next steps.
3. **Run and tabulate.** Run the judge on the same items and build the 2x2 table of human label against judge verdict.
4. **Compute.** Percent agreement, Cohen's kappa, and the judge's recall on human-labeled failures (the share of real failures it catches). A gate cares most about failures that slip through as passes.
5. **Read every disagreement.** Fix the rubric where it was unclear and the label where the label was wrong. Labeling changes what you think the criterion means (Shankar et al. call this criteria drift), so revise once, freeze the rubric, and measure again. If no held-out items remain after the revision, say so in the report.
6. **Decide per criterion.** Gate on it, report it only, or drop it, against a bar written in the design document before the numbers were seen (for example kappa of at least 0.6 and fail recall of at least 0.8; the bar is a project decision, state it as one).

Formulas, for two labels:

- percent agreement: `p_o = (both pass + both fail) / N`
- chance agreement: `p_e = P_h(pass) * P_j(pass) + P_h(fail) * P_j(fail)`, where `P_h` and `P_j` are the human's and the judge's label rates
- Cohen's kappa: `kappa = (p_o - p_e) / (1 - p_e)`; 1 is perfect agreement, 0 is chance level. In Python, `sklearn.metrics.cohen_kappa_score` computes it if scikit-learn is already a dependency; otherwise the three lines above are enough.

Worked example, usable as a unit test for your kappa function: N = 40; human 30 pass and 10 fail; judge 32 pass and 8 fail; both pass 29, both fail 7. Then `p_o = 36/40 = 0.90`, `p_e = 0.75 * 0.80 + 0.25 * 0.20 = 0.65`, `kappa = 0.25 / 0.35 = 0.71`, fail recall `7/10`. A judge that always answers pass scores `p_o = 0.75` on the same items and `kappa = 0`, which is why percent agreement alone misleads when one label dominates.

Report line format: `grounding: N=40, agreement 90% (36/40), kappa 0.71, fail recall 7/10, gating`.

## 5. Unit tests for the graders, written first

For each grader: write the tests, run them and show the failure (missing function or wrong result), implement, run again and show the pass. Keep both runs visible in the session.

Each deterministic grader gets at least:

- the golden trace: `pass`
- the known-bad variant aimed at it: `fail`, with evidence pointing at the right turn or call
- a normalization case that must pass: `"(555) 010-0197"` against `"5550100197"`
- a scenario where the check does not apply: `not_applicable`

Metric functions get hand-built event logs with known answers: a barge-in at 1200 ms and the agent's audio stopping at 1450 ms gives a 250 ms time to yield; the kappa example above; pass^k with n = 4, c = 2, k = 2 gives `1/6`.

The judge gets plumbing tests with a fake client: valid output parses; invalid JSON becomes `error`; a cache hit makes no call; the prompt contains the tool results. The judge's quality is measured by calibration, not by unit tests.

```python
def test_tool_called_fails_on_wrong_date(golden_trace, scenario):
    bad = with_tool_args(golden_trace, "reschedule_appointment", new_start="2026-03-07T09:00")
    [result] = tool_called("reschedule_appointment", {"new_start": "2026-03-17T09:00"})(bad, scenario)
    assert result.status == "fail"
    assert "2026-03-07" in result.evidence
```

## Sources

- OpenAI, evaluation best practices (pass/fail, biases, human calibration): https://developers.openai.com/api/docs/guides/evaluation-best-practices
- OpenAI, structured outputs: https://developers.openai.com/api/docs/guides/structured-outputs
- OpenAI, sampling parameters on reasoning models: https://developers.openai.com/api/docs/guides/latest-model
- Zheng et al., Judging LLM-as-a-Judge with MT-Bench and Chatbot Arena: https://arxiv.org/abs/2306.05685
- Shankar et al., Who Validates the Validators? (criteria drift): https://arxiv.org/abs/2404.12272
- scikit-learn, cohen_kappa_score: https://scikit-learn.org/stable/modules/generated/sklearn.metrics.cohen_kappa_score.html
- Pipecat Evals, function call argument subset matching: https://docs.pipecat.ai/pipecat/evals/scripted-scenarios.md
- tau-bench paper (final database state as the grade): https://arxiv.org/abs/2406.12045
