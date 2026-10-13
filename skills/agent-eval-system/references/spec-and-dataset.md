# From requirements to an eval spec and a dataset

## 1. Read the requirements for five things

From the problem statement, the agent's system prompt, its tool schemas and any policy text, extract:

1. **Call types.** The distinct jobs the agent does: book, reschedule or cancel an appointment; answer an order status question; place an outbound check call to a driver; triage a support request. Inbound and outbound calls are different call types even in one domain.
2. **Data to capture.** The fields each call type must collect and their formats: dates, times, phone numbers, account or load IDs, names, addresses, free text.
3. **Actions.** The tools that change state or end the call (writes, transfer, end call) and their order constraints: verify identity before reading account data, read a value back before writing it.
4. **Hand-off rules.** When the agent must transfer to a human, and when it must keep the call.
5. **Policies.** What the agent must never say or do: disclose another person's data, quote a price it did not look up, promise an outcome, give regulated advice, invent a result after a tool error.

## 2. Success conditions per call type

Write one row per condition. A condition is testable when it names evidence in the trace.

| Call type | Condition | Kind | Evidence in the trace | Decided by | Severity |
|---|---|---|---|---|---|
| Reschedule appointment | New slot booked for the verified caller | must | write call arguments; end state | code | critical |
| Reschedule appointment | New date read back before the write | must | agent turn before the write call contains the date | code | major |
| Reschedule appointment | Unavailable slots explained from the tool result | must | agent turn after the slot search result | judge | minor |
| Order status | Status and delivery date spoken match the lookup | must | entities in agent turns vs lookup output | code, judge for paraphrase | critical |
| Order status | No order data before identity check | must not | order of verification and lookup calls | code | critical |
| Outbound check call | Location, ETA and issues logged | must | logging call arguments | code | critical |
| Outbound check call | Voicemail: short allowed message, nothing logged | must | end reason; no logging call | code | major |
| Support line | Transfer when the caller asks for a human or policy requires it | must | transfer call within N turns | code | critical |
| Any | No forbidden phrases, no internal tool names spoken | must not | agent turns | code | critical |

Rules for the rows:

- State outcomes, not phrasings. "A booking exists for March 17 at 09:00" can be checked; "handles the call well" cannot. Exact expected sentences fail correct agents that phrase things differently.
- When the policy demands a refusal, the refusal is the success condition, together with what the agent offers instead (an alternative, a transfer, a callback). A refusal that leaves the caller with nothing still fails.
- When a pass and a fail look alike in a transcript, name the fail case: "phone ending 0197, not 0190".
- Severity drives the gate. Critical: wrong action, wrong data written, policy violation, missed transfer. Major: task not completed, needless transfer, missing read-back. Minor: style and length.

Choose metrics only after this table exists (`references/metrics.md`). Task completion aggregates the critical and major "must" rows per call, compliance aggregates the "must not" rows, latency and turn-taking come from timestamps.

## 3. Scenario schema

One scenario is one caller with one goal. Keep scenarios in data files (YAML or JSON) so a reviewer can read the test set without reading the harness. `assets/scenario.example.yaml` is a complete example.

| Field | Meaning |
|---|---|
| `id`, `call_type`, `tags`, `severity`, `description` | identity; the spec rows and edge cases it exercises |
| `persona` | who calls: name, speaking style, patience, quirks such as spelling names or correcting numbers |
| `goal` | what the caller wants, in the caller's words |
| `mode` | `scripted` (fixed user turns) or `simulated` (an LLM plays the persona) |
| `turns` | scripted user turns; each may carry `asr_text`, `interrupt_after_ms` or be a `silence_ms` pause |
| `simulator` | simulated mode only: instructions for the caller model, its model id and seed |
| `fixtures` | initial state of the fake tools (calendar, orders, loads) and injected tool failures |
| `expected` | `tool_calls` (name and argument subset), `order`, `forbidden_tools`, `forbidden_args`, `readback_before_write`, `end_state`, `transfer`, `reprompt_after_silence`, `end_reason`, `forbidden_phrases`, `judge_criteria` |
| `limits` | `max_turns`, `max_duration_s` |

Turn events at text level:

- `asr_text`: what the recognizer would output. The runner sends it instead of `user`; the expected values come from `user`. This is how text-level runs test mishearing.
- `interrupt_after_ms`: the caller starts this turn that many milliseconds after the agent's previous turn began, while the agent is still talking. The runner truncates the agent's previous turn to the characters spoken in that time at a fixed speaking rate (state the rate in the design document) and records an `agent_interrupted` event.
- `silence_ms`: the caller says nothing; the runner advances the fake clock and lets the agent's idle handling fire if it has one.

**Scripted or simulated caller.**

- Scripted: the same input every run, so failures reproduce. Best for edge cases that need exact wording or timing: a self-corrected digit, a barge-in 1.5 seconds into a long answer. A scripted caller cannot react, so its turns must work for any correct agent reply ("Yes, that's right" works after a read-back or a confirmation question).
- Simulated: an LLM plays the persona toward the goal and adapts to the agent, which finds failures nobody scripted. Runs differ, so fix the seed (and the temperature where the API accepts it), cap `max_turns`, run each simulated scenario k times and report pass^k.
- Start scripted. Add simulated scenarios for the main call types once the skeleton works.

## 4. Golden transcripts and known-bad variants

A golden transcript is a reviewed, correct conversation for one scenario, stored in the trace format: caller turns, agent turns, tool calls with arguments and results, transfer and end events, timestamps when the runner has them.

- **Grader fixtures.** Every deterministic grader must pass on the golden trace.
- **Known-bad variants.** Copy a golden trace and break one thing: the wrong date in the write call, a missing field, the transfer removed, a forbidden phrase added, the read-back removed, a result claimed after a tool error. The grader aimed at that defect must fail on it and point at the right turn. These files are unit-test fixtures and judge calibration items at the same time.
- **Judge reference.** Reference-guided grading gives the judge the golden outcome, never its wording.
- **Regression.** Compare a new run with golden outcomes (tool calls, end state), not with golden sentences.

Sources of goldens: write two or three by hand from the spec; or run the agent, review a transcript, correct it and save it; or convert recorded calls from the repository.

## 5. Voice edge cases

Simulate at text level unless the runner works with audio. Each case states the expected behavior and the check that fails when the agent gets it wrong.

| Edge case | Text-level simulation | Expected behavior | Check |
|---|---|---|---|
| Misheard numbers | `asr_text` with a teen/ty swap ("fifteen" for "fifty"), "oh" vs "zero", a dropped digit | reads back and confirms before writing; asks again when the value fails validation | write arguments equal the true value; read-back precedes the write |
| Self-correction | "0190, sorry, 0197" in one turn | uses the corrected value | arguments contain 0197, never 0190 |
| IDs and codes | swap letters that sound alike (B and D, M and N) | asks for spelling, validates the format | lookup uses the true ID; no lookup on an invalid format |
| Names | a common spelling for an uncommon name | spells back, accepts the caller's correction | stored name equals the spelled version |
| Addresses | split house numbers, missing unit, wrong street suffix | confirms the full address once | address fields equal the fixture after normalization |
| Barge-in | `interrupt_after_ms` on the next user turn | stops, does not replay the whole answer, answers the new input | next agent turn addresses the interrupting content |
| Backchannel | "uh-huh" or "okay" inside an agent turn | keeps going | no topic change or new tool call caused by the backchannel |
| Silence | `silence_ms` longer than the agent's idle timeout | reprompts once, ends politely after the allowed number of reprompts | reprompt events; `end_reason` |
| Pause mid-sentence | one user turn split by a pause (audio level only) | waits for the rest | no agent audio between the halves |
| Out of scope | a request outside the agent's job | declines briefly, says what it can do, offers a transfer if policy allows | no out-of-scope tool call; judge: no invented answer |
| Asks for a human | "let me talk to a person", repeated if ignored | transfers per policy or explains the callback path | transfer call within N turns, or the documented alternative |
| Policy violation | the caller pushes for something the policy forbids: someone else's data, skipping verification, a slot outside allowed hours, a guarantee | declines and offers an allowed alternative | any answer that breaks policy fails: forbidden tool or phrase present, or the policy judge criterion fails |
| Tool failure | fixture makes a tool return an error or time out | apologizes, does not invent a result, retries or transfers | no claimed result after the error; end state unchanged |
| Outbound surprises | voicemail, wrong person, busy caller | leaves the allowed message or offers a callback; logs nothing from a wrong person | end reason; no write call |

A scripted caller cannot hear the read-back, so follow a misheard turn with the correction the caller would give ("No, one five, fifteen"). A correct agent reads back first and receives the correction before it writes; an agent that writes at once writes the misheard value and fails the argument check. In simulated mode, tell the persona to correct any wrong read-back.

Every edge case the problem names needs at least one scenario that fails when the agent does the wrong thing.

## 6. Size and coverage

In a 90 minute build: two to four scenarios per call type plus one per named edge case, usually 12 to 25 in total. Tag each scenario with the spec rows it exercises and check that every critical row has a scenario. The report groups results by tag, so gaps show up there.

## Sources

- LiveKit, writing simulation scenarios: https://docs.livekit.io/testing/simulations/write-a-scenario.md
- LiveKit, Agent Simulations: https://docs.livekit.io/testing/simulations.md
- Pipecat Evals, scripted scenarios: https://docs.pipecat.ai/pipecat/evals/scripted-scenarios.md
- Pipecat Evals, simulated scenarios: https://docs.pipecat.ai/pipecat/evals/simulated-scenarios.md
- tau-bench paper (state-based grading, pass^k): https://arxiv.org/abs/2406.12045
- ElevenLabs Agents testing (tests created from real conversations): https://elevenlabs.io/docs/eleven-agents/customization/agent-testing
