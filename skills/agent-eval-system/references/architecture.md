# Architecture

## 1. Components

```
scenarios/*.yaml -> runner (caller + agent + fake tools) -> traces/*.jsonl
  -> graders (deterministic, then judge) -> results.jsonl
  -> report (report.md + report.json) -> gate (exit code)
```

Every stage up to the report writes files, so old traces can be re-graded without running the agent and a reviewer can open any stage. Commit the baseline and the final run's report; keep routine traces and results in a gitignored output directory or under `/tmp`.

Example layout; follow the repository's own conventions where they exist:

```
evals/
  DESIGN.md  README.md  thresholds.yaml  baseline.json
  scenarios/  golden/  labels/
  harness/    trace, runner, callers, fakes, normalize, graders, judge, metrics, report, gate
  tests/      grader, normalization, metric and judge-plumbing tests
```

## 2. Interfaces

Snippets are Python for illustration. Write the harness in the repository's language and test runner.

```python
@dataclass
class Event:
    t_ms: int
    type: str              # event types: references/metrics.md, section 1
    data: dict

@dataclass
class Trace:
    call_id: str
    scenario_id: str
    run_index: int         # repeat number, for pass^k
    events: list[Event]
    end_state: dict        # fake tools' state after the call
    meta: dict             # git SHA, model ids, seed, runner level
```

```python
class Caller(Protocol):
    def next_turn(self, events: list[Event]) -> "UserTurn | None": ...
# ScriptedCaller replays scenario.turns; SimulatedCaller asks a seeded LLM to play the persona.

def run_scenario(scenario, make_agent, caller: Caller, clock) -> Trace:
    tools = FakeTools(scenario.fixtures, clock)   # records every call and result
    agent = make_agent(tools=tools, clock=clock)  # the repository's real agent
    ...  # loop: caller turn -> agent turn, until caller returns None, call_end or limits
```

The adapter between the agent and the trace is the one piece written against the repository's internals: wrap its turn function, subscribe to its event bus, or parse its logs. Keep everything else independent of the agent so the graders survive agent refactors.

## 3. Runner level

Choose by what the repository exposes, and write the reason in the design document.

| The repository exposes | Runner | Measures | Limits |
|---|---|---|---|
| a turn function or LLM loop with tools: text in, text and tool calls out | text level: a scripted or simulated caller sends text | task, tools, policy, grounding, recovery after an injected interruption, LLM and tool latency | no real recognition errors (only simulated with `asr_text`), no voice-to-voice latency, no turn-taking |
| a media pipeline with pluggable STT, TTS and transport | audio level: synthesize caller speech, stream it through the pipeline, capture agent audio and pipeline events | all of the above plus real recognition, response latency, barge-in, turn-taking | each call runs in real time and uses audio services, so runs are slow and cost more |
| only recorded calls or logs | offline: adapt logs to the trace schema and grade them | whatever the logs contain | no new behavior is tested, since nothing runs |

Default: text level for the gate on every change, and an audio-level smoke run on a few scenarios when the pipeline allows it, reported separately. The voice frameworks' own docs draw the same line: LiveKit recommends text simulations on every commit and audio runs nightly or before release; Pipecat's text-mode evals skip STT and TTS entirely.

If the agent is built on a framework that ships an eval runner (Pipecat Evals, LiveKit's test helpers and simulations), drive the agent through that runner and keep your scenario files, graders and report as the source of truth (`references/frameworks.md`).

## 4. Running without network

When the agent cannot run offline, stub at the narrowest seam and say in the report which parts were real.

- **Tools.** Fake implementations over the scenario's `fixtures`: deterministic, recording every call, with failures injected by fixture flags (`error`, `timeout_ms`). The end state is the fakes' state after the call.
- **LLM, record and replay.** Wrap the client. On a cache miss call the real model and store the response under a hash of model, messages, tool schemas and parameters; in CI run replay-only and fail on a miss. This keeps the real agent's behavior in the gate.
- **LLM, scripted fake.** A fake client that returns the next scripted message or tool call for the scenario. Use it to build the skeleton and to test graders and the report end to end. A scripted-LLM run tests the harness, not the agent; label it that way.
- **Clock.** Inject a fake clock so latency arithmetic and idle timeouts are testable without sleeping.
- **Audio.** Synthesize caller audio once, store the files with the scenarios, and reuse them; do not call TTS on every run.

```python
class ReplayLLM:
    def __init__(self, inner, cache_dir: Path, replay_only: bool):
        self.inner, self.dir, self.replay_only = inner, cache_dir, replay_only

    def complete(self, **request) -> dict:
        path = self.dir / (sha256(json.dumps(request, sort_keys=True).encode()).hexdigest() + ".json")
        if path.exists():
            return json.loads(path.read_text())
        if self.replay_only:
            raise RuntimeError(f"cache miss in replay-only mode: {path.name}")
        response = self.inner.complete(**request)
        path.write_text(json.dumps(response))
        return response
```

## 5. Report

- **Header:** time, git SHA, agent and judge model ids, seeds, runner level, scenario and run counts, LLM mode (live, replay, scripted).
- **Metrics table:** value, N, threshold, baseline, delta, status.
- **Breakdowns:** per call type and per tag.
- **Failures:** one line per failing check: scenario, check id, severity, evidence (turn number and a short quote).
- **Judge calibration:** per criterion N, percent agreement, kappa, fail recall, and whether it gates.
- **Not measured:** each metric the runner level cannot see, with the reason.
- **Cost:** tokens and estimated spend for agent, simulated caller and judge.

Write `report.md` for people and `report.json` for the gate.

## 6. Baseline and gate

- **Baseline:** the JSON summary of an accepted run, kept in the repository. Change it only on purpose, with the reason stated where the change is reviewed.
- **Thresholds file:** the values below are placeholders; take them from the spec and the baseline, and write the reasoning in the design document.

```yaml
critical_checks_pass_rate: 1.0            # any critical failure fails the gate
task_completion: {min: 0.85, max_drop_vs_baseline: 0.05}
response_latency_p95_ms: {max: 1500}      # skipped when not measured
judge_gating_criteria: [grounding]        # calibrated criteria only
```

- **Gate command:** whatever fits the repository (`make eval-gate`, `npm run eval:gate`, a pytest marker). It runs the suite in replay mode, writes the report, prints the failing rules and exits nonzero on any failure.
- **Prove it:** make one scenario expectation wrong, or point the gate at a stored run with a known regression; run the gate and show it failing; restore; show it passing. In replay mode, changing a prompt or a fixture changes the LLM requests and only produces a cache miss.
- **CI:** a job or step that runs the gate with replay-only LLM access. Live-model and audio runs go in a separate scheduled or manual job, because they cost money and vary between runs.

## 7. Reproducibility

- Fixed seeds for simulated callers, text perturbations and any sampling of scenarios.
- Temperature 0 where the model accepts it. Some reasoning models do not support temperature and related sampling parameters while reasoning is on; for those, rely on the cache.
- Pinned model versions (dated snapshot names), recorded in each trace's `meta` and in the report header.
- Every LLM call (agent, simulated caller, judge) goes through the cache. Commit the cache only if the problem wants recorded fixtures in the repository; otherwise point it at `/tmp` and ignore it.
- Residual nondeterminism with live models is normal: repeat runs and report pass^k instead of claiming determinism.

## 8. Cost control

- Text level by default; audio runs only on a small subset.
- Hard caps per scenario: `max_turns`, `max_duration_s`, tool timeouts.
- The judge only scores criteria code cannot decide, one call per criterion per transcript, and skips criteria the scenario marks not applicable.
- The gate runs on replay, so it costs nothing after the first recording.
- After calibration, try a cheaper judge model on the same labeled set; switch only if agreement and fail recall hold.
- Count tokens per role (agent, caller, judge) and print the total in the report.
- Run scenarios concurrently with a small limit to stay inside rate limits.

## Sources

- LiveKit, Agent Simulations (text and audio modes, cadence, cost): https://docs.livekit.io/testing/simulations.md
- LiveKit, unit tests and tool mocking: https://docs.livekit.io/testing/unit-tests.md
- Pipecat Evals overview (text and audio modes): https://docs.pipecat.ai/pipecat/evals/overview.md
- OpenAI, sampling parameters on reasoning models: https://developers.openai.com/api/docs/guides/latest-model
- promptfoo, caching of provider calls: https://www.promptfoo.dev/docs/configuration/caching/
- tau-bench paper, pass^k: https://arxiv.org/abs/2406.12045
