# Reuse or build

## Decision

Default to a small harness inside the repository: scenario files, a runner, graders, a report and a gate, written in the repository's language with its test runner. In a 90 minute build this costs less than learning and configuring a framework, adds no dependency to the pull request, and shows the design decisions to the reviewer.

Adopt a framework instead when one of these holds:

- the repository already depends on it (check `pyproject.toml`, `requirements*.txt`, `package.json`, CI files);
- the problem statement asks for it;
- the agent is built on a voice framework with its own test runner (Pipecat, LiveKit Agents). Then drive the agent through that runner and keep your scenario files, graders and report as the source of truth.

Hosted platforms (voice QA products, the voice platforms' own test suites) fit production QA with real phone calls at scale. They need accounts and send call data outside the repository, so in a timed in-repository build mention them under next steps, not in the implementation.

## General LLM and agent evaluation frameworks

| Name | What it is | Use it when | Official URL |
|---|---|---|---|
| promptfoo | Open-source CLI and library for evaluating and red-teaming LLM apps; assertions include `llm-rubric` (LLM as judge), a simulated-user provider inspired by tau-bench, and response caching | you want declarative YAML test matrices across prompts and providers, run from the command line or CI | https://www.promptfoo.dev/docs/intro/ |
| DeepEval | Open-source LLM evaluation framework with pytest-style assertions; metrics include G-Eval (judge with custom criteria) and Tool Correctness, plus a conversation simulator | the repository is Python on pytest and you want ready-made agent and judge metrics | https://deepeval.com/docs/introduction |
| OpenAI Evals API | Hosted eval runs on the OpenAI platform. Being retired: read-only for existing users on October 31, 2026, scheduled to shut down on November 30, 2026 | do not start new work on it | https://developers.openai.com/api/docs/guides/evals |
| openai/evals | Open-source framework and registry of benchmarks for evaluating LLMs and LLM systems | the repository already has evals in this registry format | https://github.com/openai/evals |
| Inspect AI | Open-source evaluation framework from the UK AI Security Institute and Meridian Labs: datasets, solvers, scorers, agents, sandboxes, a log viewer | Python, agentic tasks that need sandboxed tools, many models compared | https://inspect.aisi.org.uk/ |
| Braintrust | Platform for tracing and evaluating AI applications: an eval is a dataset, a task and scorers; the open-source `autoevals` library supplies scorers | the team already logs to Braintrust, or you want `autoevals` scorers without the platform | https://braintrust.dev/docs/evaluation-quickstart |
| LangSmith evaluation | Datasets, evaluators, LLM-as-judge evaluators and multi-turn simulation in LangSmith | the agent is built with LangChain or LangGraph, or already traces to LangSmith | https://docs.langchain.com/langsmith/evaluation-concepts |
| Arize Phoenix | Open-source AI observability platform built on OpenTelemetry, with code-based and LLM-as-judge evaluators over traces and datasets | the agent already emits OpenTelemetry traces | https://arize.com/docs/phoenix |
| Ragas | Open-source evaluation framework for LLM applications, including RAG pipelines and agents; agent metrics include topic adherence and tool call accuracy | the agent answers from a knowledge base and retrieval quality matters | https://docs.ragas.io/ |

## Agent and user simulation

| Name | What it is | Use it when | Official URL |
|---|---|---|---|
| tau-bench (Sierra) | Benchmark of conversations between an LLM-simulated user and a tool-using agent under domain policies; grades by comparing the final database state with the goal state; introduced pass^k | you need the method (state-based grading, simulated users, pass^k), not its airline and retail tasks | https://github.com/sierra-research/tau-bench |
| tau2-bench (now tau3) | The maintained successor: more domains, fixed tasks, and a full-duplex voice evaluation mode using realtime audio APIs | you want reference voice-agent benchmark tasks or its simulator design | https://github.com/sierra-research/tau2-bench |

## Voice frameworks with built-in testing

| Name | What it is | Use it when | Official URL |
|---|---|---|---|
| LiveKit Agents testing | Turn-level unit tests on pytest or Vitest with assertions on messages and tool calls (name and arguments), `judge()` against an intent, `mock_tools`; Agent Simulations with an LLM caller in text or audio mode, which run on LiveKit Cloud | the agent is built on LiveKit Agents | https://docs.livekit.io/testing/ |
| Pipecat Evals | Scripted and simulated scenarios in YAML run against the real pipeline: substring and judge checks, function call argument subsets, latency budgets, interruption events, repeated runs in suites, text and audio modes | the agent is built on Pipecat | https://docs.pipecat.ai/pipecat/evals/overview |

## Voice platforms' own testing (relevant only when the agent is hosted there)

| Name | What it is | Official URL |
|---|---|---|
| Vapi Evals and Simulations | Evals check the next turn from a mock conversation at the text and model layer (no speech recognition or turn-taking); Simulations run an AI tester through a full voice or chat call with success criteria and latency limits | https://docs.vapi.ai/observability/evals-quickstart , https://docs.vapi.ai/observability/simulations-overview |
| Retell AI simulation testing | An AI-simulated caller runs a test case as a text conversation, graded by success criteria, with function mocks and batch runs | https://docs.retellai.com/test/llm-simulation-testing |
| ElevenLabs Agents testing | Three test types: full simulated conversations, next-reply checks against criteria, and tool call checks on name and parameters | https://elevenlabs.io/docs/eleven-agents/customization/agent-testing |

## Voice QA platforms (hosted, third party)

All five simulate calls before launch and score production calls; Pipecat's documentation lists Bluejay, Cekura, Coval and Roark as eval platform integrations.

| Name | What it is | Official URL |
|---|---|---|
| Coval | Simulates voice and chat conversations before launch and evaluates uploaded production conversations; connects to Pipecat and LiveKit agents among others | https://docs.coval.ai/ |
| Hamming | Voice and chat agent QA: generated scenarios, replay of production calls, production monitoring | https://hamming.ai/ |
| Cekura | Testing and observability for voice AI agents: simulated conversations, LLM-judge and code metrics, production call monitoring | https://docs.cekura.ai/ |
| Bluejay | QA and observability for voice and chat agents: simulations, load tests, production monitoring, evaluations | https://docs.getbluejay.ai/ |
| Roark | Quality platform for voice and chat AI: simulations with personas and background-noise environments, scoring of production calls | https://docs.roark.ai/ |

## Sources

- promptfoo: https://www.promptfoo.dev/docs/intro/ , https://www.promptfoo.dev/docs/configuration/expected-outputs/model-graded/llm-rubric/ , https://www.promptfoo.dev/docs/providers/simulated-user/ , https://www.promptfoo.dev/docs/configuration/caching/
- DeepEval: https://deepeval.com/docs/introduction , https://deepeval.com/docs/metrics-llm-evals , https://deepeval.com/docs/metrics-tool-correctness , https://deepeval.com/docs/conversation-simulator
- OpenAI Evals API deprecation: https://developers.openai.com/api/docs/guides/evals
- openai/evals: https://github.com/openai/evals
- Inspect AI: https://inspect.aisi.org.uk/
- Braintrust: https://braintrust.dev/docs/evaluation-quickstart , https://github.com/braintrustdata/autoevals
- LangSmith: https://docs.langchain.com/langsmith/evaluation-concepts , https://docs.langchain.com/langsmith/multi-turn-simulation
- Arize Phoenix: https://arize.com/docs/phoenix , https://arize.com/docs/phoenix/evaluation/llm-evals
- Ragas: https://docs.ragas.io/ , https://docs.ragas.io/en/stable/concepts/metrics/available_metrics/agents/
- tau-bench: https://arxiv.org/abs/2406.12045 , https://github.com/sierra-research/tau-bench , https://github.com/sierra-research/tau2-bench
- LiveKit: https://docs.livekit.io/testing/unit-tests.md , https://docs.livekit.io/testing/simulations.md
- Pipecat: https://docs.pipecat.ai/pipecat/evals/overview.md , https://docs.pipecat.ai/llms.txt
- Vapi: https://docs.vapi.ai/observability/evals-quickstart.md , https://docs.vapi.ai/observability/simulations-overview.md
- Retell AI: https://docs.retellai.com/test/llm-simulation-testing.md
- ElevenLabs: https://elevenlabs.io/docs/eleven-agents/customization/agent-testing.md
- Coval: https://docs.coval.ai/ ; Hamming: https://hamming.ai/ ; Cekura: https://docs.cekura.ai/llms.txt ; Bluejay: https://getbluejay.ai/llms.txt ; Roark: https://docs.roark.ai/llms.txt
