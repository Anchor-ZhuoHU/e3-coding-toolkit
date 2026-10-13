# Judge rubric template

One file per criterion. Replace every <...>. Keep the examples short, and keep them out of the calibration set.

## Prompt

```text
You grade one phone call transcript against one criterion. Use only the transcript,
the tool calls and results shown inline, the scenario, and the policy excerpt.
Decide this criterion only. Length is not a merit.

Criterion: <id>: <one sentence, for example "Every fact the agent states about the
order is supported by a tool result in this call.">
Pass when: <observable conditions>
Fail when: <observable conditions>
Not applicable when: <for example "the agent states no facts about the order">
Hard cases: <for example "rounding a delivery window to the hour passes; a different day fails">

Examples:
<3 to 6 transcript lines> => {"verdict": "pass", "reasoning": "<one sentence>"}
<3 to 6 transcript lines> => {"verdict": "fail", "reasoning": "<one sentence>"}
<borderline case> => {"verdict": "<pass or fail>", "reasoning": "<why>"}

Scenario goal: {goal}
Expected outcome: {expected_outcome}
Policy excerpt: {policy}
Transcript (numbered turns, tool calls and results inline):
{transcript}

Reply with JSON only. Write the reasoning before the verdict.
```

## Output schema

```json
{
  "type": "object",
  "properties": {
    "criterion": {"type": "string"},
    "reasoning": {"type": "string"},
    "verdict": {"type": "string", "enum": ["pass", "fail", "not_applicable"]},
    "evidence_turns": {"type": "array", "items": {"type": "integer"}}
  },
  "required": ["criterion", "reasoning", "verdict", "evidence_turns"],
  "additionalProperties": false
}
```

## Before the judge enters the gate

- Labels for 20 to 40 items exist, made by a person before the judge ran (or fixed by construction, and reported as such).
- Percent agreement, Cohen's kappa and fail recall are in the report, with N.
- The rubric is frozen; the version used for the numbers is the version in the repository.
- The gating bar was written in the design document before the numbers were seen.
