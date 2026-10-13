# Platform migration checklist

Use this when a PR moves a voice agent from one voice or telephony platform to another: for example from a hosted voice agent API to a self-run media pipeline, or from one carrier's webhooks and media streams to another's. Each item is a question to answer from the code, followed by the defect it usually hides.

Before reading the new adapter, build a parity table in the notes:

| Behavior | Old path (file:line) | New path (file:line) | Same? |
| --- | --- | --- | --- |

List every behavior the old path had, then fill the new column. An empty cell in the new column is a finding or a question.

## 1. Behavior parity

- Greeting and first turn: who speaks first, how quickly, and what happens when the caller speaks first.
- Interruption: caller speech stops agent audio on the new platform, and unplayed text is dropped instead of spoken later.
- Silence: re-prompt after some seconds of silence, hang up after a longer limit.
- End of call: how the agent hangs up, and whether the call ends when the agent process ends.
- DTMF: digits received from the caller and digits sent (extensions, menus).
- Voicemail and answering machines on outbound calls.
- Recording and transcription, including any consent prompt.
- Caller ID, call metadata, and custom parameters passed into the agent (account ID, language, campaign).
- Language, voice, and speech settings.
- Maximum call duration.
- Transfers the old path already had (cold transfer, forwarding) still work.

Typical defect: the old platform did something implicitly (for example, hanging up when the agent finished) and the new path has no code for it.

## 2. Feature flag and gradual rollout

- A flag or routing rule picks the old or new path per call (by number, tenant, or percentage), and the new path is off by default.
- The choice is made once at call start and stored with the call. A call never switches platform because the flag changed mid-call.
- One function reads the flag. Scattered `if new_platform:` checks drift apart.
- The flag flips without a deploy, and flipping it back is the rollback.
- Metrics carry the platform as a label, so the two paths can be compared during rollout.

Typical defect: a webhook handler reads the flag again, so a flip during a call sends the rest of that call's events to the wrong handler.

## 3. Backward compatibility

- Webhook URLs: old routes keep working until every phone number and provider setting points at the new ones. Removing a route breaks every number still configured with it.
- Payload formats: event names, field names, enum values, and timestamp formats that other code reads (call records, analytics events, CRM updates). Compare one payload from each path field by field.
- Configuration: renamed environment variables still accept the old name, or startup fails with a message naming the new one. Defaults do not change unless the PR says why.
- Stored data: new columns are nullable or defaulted, old rows still load, and IDs from the old platform still resolve.

Typical defect: downstream code looks calls up by the old platform's call ID while the new platform's events carry a room or session name, so call records stop updating and nothing reports an error.

## 4. Rollback path

- Rolling back is a flag flip or a config change, not a revert plus a data repair.
- Schema changes are additive in this PR; removals wait for a later one.
- Calls already running on the new platform can finish after a rollback.
- The PR or its docs say how to roll back and how to confirm the rollback worked.

## 5. State and in-flight calls at cutover

- A call that started on the old platform finishes there, and its late webhooks (final status, recording ready) still reach the old handler. Route those events by the platform stored on the call, not by the current flag value.
- The old platform's ID and the new platform's ID (call SID, room name, session ID) both map to one internal call ID.
- When more than one instance handles webhooks, call state lives in a shared store (database, cache), not in process memory.
- Work scheduled before cutover (callbacks, retries, reminders) still runs, on the platform that matches the call.
- Data the new platform needs before the first call (phone number assignments, agent and voice settings, transfer destinations) is created by a script or a documented step, and the PR says which.

Typical defect: an in-memory dictionary holds call state; the next webhook for the call reaches another instance, finds nothing, and treats the call as new.

## 6. Secrets and configuration

- New credentials come from the environment or a secret store, never from code, fixtures, or a committed `.env` file.
- Missing configuration fails at startup with a clear message, not on the first live call.
- Secrets never reach logs, error messages, or tracebacks. Check how config objects print and whether HTTP client debug logging is on.
- Tokens carry the least privilege needed, for example a token that can join only one room.
- Test and production credentials are separate.

## 7. Error handling and retries

- Every call to the platform API has a timeout.
- Retries use backoff and wrap only idempotent operations. Retrying "create outbound call" or "add participant" without a guard dials the human twice.
- A failed API call during a live call leads to something the caller hears: an apology, a retry, a fallback to the AI.
- Exceptions in background tasks are logged and handled; they never end a call silently.

## 8. Webhook idempotency and ordering

- Each handler derives a deduplication key: the provider's event ID, or the call ID plus event type plus sequence number.
- Side effects (database writes, outbound calls, transfers) run once per key; a repeated delivery returns success without repeating them.
- Handlers accept events in any order. A terminal state (completed, failed, canceled) is never overwritten by a late non-terminal event (ringing).
- Providers retry deliveries that fail or time out (Twilio retries once on a connection timeout by default; LiveKit retries several times), so a slow handler causes duplicates. Handlers answer quickly and move slow work off the request.

## 9. Webhook signature validation

- Every public webhook route validates the provider's signature with the provider's SDK helper before any side effect.
- Validation uses the raw request body and the exact public URL the provider called. Behind a proxy or load balancer, the scheme, host, or port the app sees can differ from that URL, and the check then fails or gets switched off.
- No setting disables validation in production. Tests cover a missing signature and a wrong one.
- WebSocket media endpoints require a token or a short-lived secret too, because anyone who learns the URL can open a stream.

## 10. Timeouts

- Webhook handlers respond within the provider's limit (Twilio's default total time for a webhook request, retries included, is 15 seconds).
- The outbound ring timeout is set explicitly.
- Hold has a maximum duration, after which the caller gets a fallback.
- Summary generation and other LLM calls on the transfer path have a timeout and a fallback text.
- Maximum call duration and idle timeouts match the old path.

## 11. Observability

- One internal call ID appears in every log line, metric, and trace for the call, across every leg of a transfer, and is linked to each platform ID.
- Every state transition is logged with the old state, the new state, and the reason.
- Metrics exist for transfer attempts, outcomes by reason (answered, no answer, busy, voicemail, caller left, error), and time on hold, labeled by platform during rollout.
- No PII in logs: phone numbers masked, no transcripts or summaries at info level, no raw webhook bodies.

## 12. Tests for both paths

- While the flag exists, the old and new paths both have tests.
- Payload parsing tests use sample payloads taken from the provider's docs.
- Failure paths have tests: no answer, busy, voicemail, caller hang-up, duplicate and out-of-order webhooks, invalid signature.
- Tests use a fake platform client and never call the real network.

## 13. Audio format

- Codec and sample rate match at every boundary: the phone leg, speech-to-text input, text-to-speech output, recordings.
- Example: Twilio Media Streams carry mu-law audio at 8000 Hz, base64 encoded, in both directions. A pipeline running at 16 or 24 kHz must resample and re-encode at that edge.
- A mismatch sounds like static, sped-up or slowed speech, or silence, or shows up as speech-to-text returning nothing.
- Chunk size and buffering: how long each audio frame is, and whether buffered agent audio is cleared when the caller interrupts.

## Sources

- Twilio Media Streams WebSocket messages: https://www.twilio.com/docs/voice/media-streams/websocket-messages
- Twilio webhook security: https://www.twilio.com/docs/usage/webhooks/webhooks-security
- Twilio webhook connection overrides (timeouts and retries): https://www.twilio.com/docs/usage/webhooks/webhooks-connection-overrides
- Twilio Call resource (status callbacks): https://www.twilio.com/docs/voice/api/call-resource
- LiveKit webhooks and events: https://docs.livekit.io/intro/basics/rooms-participants-tracks/webhooks-events
