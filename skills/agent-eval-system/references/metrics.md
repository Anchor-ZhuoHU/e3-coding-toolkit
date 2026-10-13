# Metrics: definitions and how to compute them from a trace

## 1. The event log every metric reads

Record one event per line, per call, with `t_ms` measured from call start on a monotonic clock. Metrics are pure functions of this log: they can be unit-tested on hand-built logs and recomputed on old runs.

| Event `type` | Data | Text-level runner | Audio-level runner |
|---|---|---|---|
| `user_speech_start`, `user_speech_end` | | not available | caller audio track or VAD |
| `user_transcript` | `text`, `final` | the scripted or simulated text (or `asr_text`) | STT final transcript |
| `agent_llm_request`, `agent_llm_first_token` | `model` | LLM client wrapper | LLM client wrapper |
| `agent_text` | `text` | agent output | text sent to TTS |
| `agent_audio_start`, `agent_audio_end` | | not available | first and last audio frame out |
| `agent_interrupted` | `chars_spoken` | injected by the runner | framework event |
| `tool_call`, `tool_result` | `id`, `name`, `args` / `output`, `error` | fake tools | fake or real tools |
| `reprompt` | `reason` | agent idle handler | agent idle handler |
| `transfer`, `call_end` | `reason` | agent tool call | agent tool call |

A metric whose events are missing is reported as "not measured" with the reason, never as zero.

## 2. Task metrics

**Task completion rate.** A call is complete when all its critical and major "must" checks pass. Rate = complete calls / graded calls, per call type and overall. Base it on end-state checks (the fake tools' state after the call against the expected state) wherever an action is involved. tau-bench grades agents the same way, comparing the final database state with the annotated goal state, which stays objective while the wording of each conversation varies.

**Reliability, pass^k.** A live model or a simulated caller makes runs differ. Run each such scenario n times; with c successes, `C(c, k) / C(n, k)` estimates the chance that k independent runs all succeed; average it over scenarios (tau-bench's definition). pass^1 is the plain success rate. A large gap between pass^1 and pass^k means the agent succeeds by luck.

```python
from math import comb

def pass_hat_k(runs_by_scenario: dict[str, list[bool]], k: int) -> float:
    scores = []
    for runs in runs_by_scenario.values():
        n, c = len(runs), sum(runs)
        if n < k:
            raise ValueError(f"need at least {k} runs, got {n}")
        scores.append(comb(c, k) / comb(n, k))
    return sum(scores) / len(scores)
```

**Containment and transfer.** Containment rate = calls that ended without a transfer to a human / all calls; transfer rate = 1 minus containment (Google's contact center analytics call it escalation rate: the percentage of conversations escalated to a human agent). Containment is not success: a contained call that failed its task is worse than a correct transfer. Grade transfers against each scenario's `expected.transfer`:

| | transfer expected | transfer not expected |
|---|---|---|
| agent transferred | correct transfer | unnecessary transfer (major) |
| agent kept the call | missed transfer (critical) | correct containment |

Also report "contained and completed": calls with no transfer and a completed task / all calls.

**Field capture accuracy (speech robustness).** For each required field, compare the normalized captured value with the expected one. Report it per field type (number, ID, name, address, date), separately for scenarios with injected recognition errors and clean ones; the difference is the cost of mishearing. When reference transcripts of real audio exist, word error rate `WER = (S + D + I) / N` (substitutions, deletions, insertions over reference words) measures the recognizer; field accuracy measures whether the agent recovered anyway.

**Policy compliance.** Calls with zero critical violations / all calls. Violations come from deterministic checks (forbidden tools, forbidden phrases, data before verification, write without read-back) and from calibrated judge criteria for rules code cannot express. Report each violation type separately; a single number hides which rule broke.

**Hallucination (grounding).** Deterministic part: every number, date, amount, ID or status the agent says must appear in a tool result from this call, in data the agent was given, or in the caller's own words. Ungrounded entity rate = agent entities with no source / agent entities. Judged part: a grounding criterion that sees the tool results and decides whether each factual claim is supported. A result claimed after a tool error counts as a hallucination.

**Efficiency.** Agent turns to completion, call duration, tool calls per call, and repeated questions (a field asked for again after the caller confirmed it).

## 3. Voice metrics

**Response latency.** For each user turn the agent answers: `agent_audio_start - user_speech_end`. This is the silence the caller hears; LiveKit's per-turn `e2e_latency` measures the same span, from the user stopping speaking to the agent starting to respond. Report p50, p95 and max per call type; a mean hides the slow tail. Measured on the caller's side (when the simulated caller receives audio), it also includes transport and playback delay; LiveKit's audio simulations report this caller-heard value and advise tracking it separately from the latency the agent reports. A negative value means the agent started before the caller finished: count it as a cut-in (below), not as a fast answer. Break the latency down when the events exist:

- end-of-turn delay: end of speech to the decision that the caller finished (LiveKit reports it as `end_of_turn_delay`)
- LLM time to first token: `agent_llm_first_token - agent_llm_request`
- TTS time to first audio: from the first text sent to TTS to the first audio chunk (Pipecat reports TTFA per TTS service)
- tool time: `tool_result - tool_call`, for turns that call tools

At text level only the LLM and tool times exist. Report them under those names and mark response latency "not measured".

**Interruption handling (barge-in).** For each `user_speech_start` that falls inside an agent audio span:

- time to yield = the agent's next `agent_audio_end` or `agent_interrupted` minus `user_speech_start`; report p50 and p95
- yield rate = barge-ins where the agent stopped within the budget / barge-ins
- false interruption rate = agent stops with no caller words transcribed / agent stops (LiveKit calls a stop with an empty transcript a false interruption)
- backchannel robustness = backchannel-only utterances ("uh-huh", "okay") that did not stop the agent / backchannel utterances
- recovery = interrupted turns whose next agent turn answers the interrupting content without replaying the whole cut answer (judge criterion, or a check on the next turn's content)

At text level only recovery is measurable, using the runner's injected `agent_interrupted` event.

**Turn-taking.**

- cut-ins = agent audio starting while the caller is still speaking, where the caller was not barging in; per call
- overlap share = time both sides speak at once / call duration
- unanswered turns = caller turns with no agent response before the next caller turn or the end of the call
- dead air = gaps after a finished caller turn longer than a threshold set in the design document

LiveKit's audio simulations report the same families (end-of-turn mispredictions, time to yield, false interruptions, overlap, unfilled silences, unanswered turns), which makes them a cross-check when the agent runs on that framework.

**Silence handling.** For scenarios with `silence_ms`: time from the last agent turn to the `reprompt` event (it should match the configured idle timeout within a stated tolerance), number of reprompts before the call ends, and whether `call_end.reason` is the idle timeout rather than an error.

## 4. Aggregation

- Compute each metric per scenario, per call type, per tag (edge case) and overall.
- Print N next to every rate, and counts for small N: `7/9 (78%)`.
- For repeated runs, state k next to pass^k.
- Against the baseline, show the delta per metric and the list of scenarios that passed in the baseline and fail now; the scenario list explains the metric delta.

## Sources

- LiveKit, per-turn latency fields and metrics: https://docs.livekit.io/testing/observability/data.md
- LiveKit, turn detection and false interruptions: https://docs.livekit.io/agents/logic/turns.md
- LiveKit, adaptive interruption handling (backchanneling): https://docs.livekit.io/agents/logic/turns/adaptive-interruption-handling.md
- LiveKit, audio simulation measurements: https://docs.livekit.io/testing/simulations.md
- Pipecat, metrics (TTFB, TTFA): https://docs.pipecat.ai/pipecat/fundamentals/metrics.md
- Pipecat, interruptions: https://docs.pipecat.ai/pipecat/fundamentals/interruptions.md
- Pipecat, idle users: https://docs.pipecat.ai/pipecat/fundamentals/detecting-user-idle.md
- tau-bench paper, pass^k and state-based grading: https://arxiv.org/abs/2406.12045
- Google Cloud, escalation rate definition: https://docs.cloud.google.com/contact-center/insights/docs/virtual-agent-platform
- Hugging Face evaluate, WER: https://github.com/huggingface/evaluate/blob/main/metrics/wer/README.md
