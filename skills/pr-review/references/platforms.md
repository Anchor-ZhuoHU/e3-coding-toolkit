# Warm transfer on common voice platforms

How each platform's official docs and examples build a warm transfer, the events the code has to handle, and the pitfalls to check in a PR. Every fact below comes from the official pages listed under Sources. When a PR depends on a detail that is not here, check the current docs before calling it a bug.

## Side by side

| Step | Twilio | LiveKit | Pipecat on Daily | Vapi | Retell |
| --- | --- | --- | --- | --- | --- |
| Hold the caller | Conference participant update `Hold=true` with `HoldUrl`; `waitUrl` before the conference starts | Disable the agent session's audio input and output; play hold audio | `MixerEnableFrame(True)` on a `SoundfileMixer`; a mute strategy gates caller audio | `holdAudioUrl` | On-hold music setting |
| Reach the human | Participants API create: an outbound call into the conference | `CreateSIPParticipant` into a separate consultation room | `transport.start_dialout(...)` | Transfer Call tool destination | Transfer Call tool destination |
| Brief the human | Before the human joins, or `AnnounceUrl` or coaching (`CallSidToCoach`) aimed at one participant | A transfer agent talks to the human in the consultation room | The official example briefs in the shared room after unholding, so the caller hears it | Message or summary modes speak on the destination leg | Whisper debrief, heard only by the destination |
| Connect | The human joins the caller's conference; unhold the caller | `MoveParticipant` moves the human into the caller's room | Unhold the caller; the bot stays as the bridge | Traditional modes connect after the message or summary; assistant-based mode connects on `transferSuccessful` | Bridge after the warm or agentic step |
| AI leaves | Remove the AI's leg; it must not have `endConferenceOnExit=true` | Both agents leave their rooms | The bot stays: if it leaves, the room ends | Not described in the pages used here | The agent drops off after connecting |
| Failure signal | Outbound leg status `no-answer`, `busy`, `failed`, `canceled`; conference `participant-leave` with `ParticipantCallStatus` | `SipCallError` with the SIP status; participant `disconnect_reason` | `on_dialout_error`, or `on_dialout_stopped` before answer | `transferCancel`, then `fallbackPlan` | Unanswered after the ring duration; agentic mode applies its action on timeout |

## Twilio (Programmable Voice)

### Primitives

- Conference: `<Dial><Conference>` TwiML puts a call into a named conference. Twilio documents Conference as the container for hold, transfer, and barge, and defines a warm transfer as adding a participant and letting all three talk before the initiator drops off.
- Participants API, create: places an outbound call and adds it to the conference. Parameters that matter: `Timeout` (ring time, 5 to 600 seconds, default 60, and Twilio adds a 5-second buffer), `StatusCallback` with `StatusCallbackEvent` (`initiated`, `ringing`, `answered`, `completed`; default `completed`), `MachineDetection`, `Label`, `EndConferenceOnExit`, `EarlyMedia`.
- Participants API, update: `Hold` with `HoldUrl` (MP3, WAV, or TwiML using `<Play>`, `<Say>`, `<Pause>`, `<Redirect>`), `Muted`, `AnnounceUrl` (plays to that participant), `Coaching` with `CallSidToCoach` (only the coached participant hears the coach). Delete removes a participant from the conference.
- Call update: set `Twiml` or `Url` on a live call to replace what it is executing (for example, to move the caller from a media stream into a conference), or set `Status` to `canceled` (a queued or ringing call) or `completed`.
- Answering machine detection: `MachineDetection=Enable` reports `AnsweredBy` as `human`, `machine_start`, `fax`, or `unknown`. Synchronous detection holds the call until it decides; asynchronous detection uses one of the four forked streams a call may have.
- Media Streams: `<Connect><Stream>` exchanges mu-law audio at 8000 Hz, base64 encoded, over a WebSocket. A bidirectional stream ends when the call ends or the server closes the socket. When the server closes it, Twilio requests the `<Connect>` `action` URL if one is set, or else runs the TwiML after `<Connect>`.
- ConversationRelay: the app ends the AI session with an `end` message carrying `handoffData`; Twilio passes it as `HandoffData` to the `<Connect>` `action` URL, whose TwiML performs the transfer. Twilio says not to put PCI data in `handoffData`.

### How the pieces fit

Twilio's warm transfer tutorial puts the caller in a conference named after the caller's CallSid and stores that name so later legs can join. The caller joins with `startConferenceOnEnter=false`, so it hears wait music until an agent arrives. The first agent's leg has `endConferenceOnExit=false` so it can leave; the caller and the second agent have `endConferenceOnExit=true`, so the call ends when either of them hangs up. With an AI agent the shape stays the same: the caller's call moves into a conference (a call update with new TwiML), the AI is a leg that can leave, and the human joins as a participant created through the API.

### Events

- Conference status callbacks, selected with `statusCallbackEvent`: `start`, `end`, `join`, `leave`, `mute`, `hold`, `modify`, `speaker`, `announcement`. Parameters include `SequenceNumber`, `ReasonConferenceEnded`, and on `participant-leave` both `ParticipantCallStatus` (`no-answer`, `busy`, `in-progress`, `failed`, `canceled`, `completed`) and `ReasonParticipantLeft` (which includes `participant_add_failed`).
- Call status callbacks per leg: `CallStatus` is one of `queued`, `initiated`, `ringing`, `in-progress`, `completed`, `busy`, `failed`, `no-answer`, `canceled`.
- The AMD result, carried in `AnsweredBy`.

### Pitfalls to check

- Status callbacks are separate HTTP requests, and Twilio states there is no guarantee they arrive in order. Use `SequenceNumber`, and never let a late event overwrite a terminal state.
- The first participant to join sets the conference's `statusCallbackEvent` list; later values are ignored. If the caller's TwiML joins first without events, the PR receives no conference events.
- A conference starts only when at least two participants are in it and one has `startConferenceOnEnter=true`. Until then participants hear wait music.
- `endConferenceOnExit=true` on the AI's leg ends the call for everyone when the AI leaves.
- A `waitUrl` or `HoldUrl` TwiML document that runs out of verbs plays silence; loop it with `<Redirect>`. If the `waitUrl` request fails, the conference is not fully established.
- By default an account can create one call per second through the Participants API.
- Twilio warns against putting PII in a conference's friendly name; name conferences after an internal ID.
- Signatures: `X-Twilio-Signature` is an HMAC-SHA1, keyed with the auth token, over the webhook URL and the request parameters. Use the SDK validator rather than rebuilding the parameter list, because Twilio adds parameters without notice. The URL must be the one Twilio called, as seen from outside any proxy.
- Retries: by default a webhook is retried once on a connection timeout, within a 15-second total budget. The `I-Twilio-Idempotency-Token` header identifies retries of the same request.

## LiveKit

### Primitives

- Rooms and participants: a phone caller is a SIP participant in a room; the agent is another participant.
- `CreateSIPParticipant`: dials out and adds the callee to a room. With `wait_until_answered` the request returns after the answer; `ringing_timeout` caps ringing, with an upper limit of 80 seconds.
- `MoveParticipant`: moves a participant into another room. Available only on LiveKit Cloud, and the caller of the API needs the `roomAdmin` grant.
- `TransferSIPParticipant`: a cold transfer by SIP REFER. The trunk must allow transfers. `ringing_timeout` defaults to 30 seconds; on timeout the request returns an error and the caller stays in the room. Caller ID for the transfer is set on the trunk, not per request.
- `WarmTransferTask`, a prebuilt task (Python `livekit.agents.beta.workflows`, Node.js `workflows`): dials the human, plays hold audio (built-in hold music by default), disables the caller's audio I/O, gives the human the conversation history, and offers the human `connect_to_caller`, `decline_transfer`, and `voicemail_detected` tools. Parameters include `sip_call_to`, `sip_trunk_id` or `sip_connection`, `dtmf`, `ringing_timeout`, `hold_audio`, and `extra_instructions`. On ring timeout it ends with a `ToolError` and the caller conversation resumes. It returns `human_agent_identity`.
- Answering machine detection: classifies the answer once, on the first utterance, as `human`, `machine-ivr`, `machine-vm`, `machine-unavailable`, or `uncertain`.

### How the pieces fit (the manual workflow in the docs)

1. Put the caller on hold with `session.input.set_audio_enabled(False)` and `session.output.set_audio_enabled(False)`, then start hold music.
2. Create a consultation room, connect a transfer agent with a token for that room, and dial the human into it with `CreateSIPParticipant`.
3. The transfer agent summarizes the call from a copy of the caller session's chat context.
4. `MoveParticipant` moves the human into the caller's room; the first agent may introduce them.
5. Both agents leave, and the caller and the human continue.

### Events

- The SIP participant attribute `sip.callStatus`: `dialing`, `ringing`, `automation` (still sending DTMF), `active`, `hangup`.
- `disconnect_reason` on SIP participants: `USER_REJECTED` (SIP 486 or 603), `USER_UNAVAILABLE` (408 or 480), `SIP_TRUNK_FAILURE`, `CLIENT_INITIATED`, `ROOM_DELETED`. With `wait_until_answered`, failures before the answer raise `SipCallError` with the SIP status code.
- Webhooks such as `participant_left` and `room_finished`, each with an `id` usable for deduplication.

### Pitfalls to check

- `wait_until_answered` also returns when voicemail answers. Before connecting the caller, the PR needs detection or a confirmation step; `WarmTransferTask` has the `voicemail_detected` tool, manual code needs its own.
- After `USER_UNAVAILABLE` or `SIP_TRUNK_FAILURE` the session is not closed automatically; the code must shut it down or return to the caller.
- `MoveParticipant` does not exist on self-hosted LiveKit, so a PR targeting a self-hosted server needs another way to join the legs.
- Hold must disable input as well as output. With only output disabled, the session still receives the caller's audio, so what the caller says on hold reaches the conversation.
- The message telling the human that the caller hung up (`callerHangupInstruction`) exists only in the Node.js task. In Python, check how the PR handles a caller who leaves mid-transfer.
- Webhooks carry an `Authorization` header holding a signed JWT that includes a SHA-256 hash of the body. Validate with `WebhookReceiver` on the raw body. LiveKit retries deliveries and does not guarantee them, so handlers must be idempotent.
- Token scope: in the docs the transfer agent's token grants only the consultation room; only the code that calls `MoveParticipant` needs `roomAdmin`.

## Pipecat

### Primitives

- Transports: `DailyTransport` for Daily phone numbers and SIP; `FastAPIWebsocketTransport` with a frame serializer (such as `TwilioFrameSerializer`) for carrier media streams over WebSocket.
- Daily calls: `transport.start_dialout(...)` dials a number; `transport.sip_call_transfer(...)` is the cold transfer call in the docs' example.
- Daily transport events: `on_dialout_connected`, `on_dialout_answered`, `on_dialout_stopped`, `on_dialout_warning`, `on_dialout_error`, `on_participant_left`.
- Frames used by the official warm transfer example: `MixerEnableFrame` with a `SoundfileMixer` for hold music, a mute strategy toggled by a custom hold frame to gate caller audio, `LLMMessagesAppendFrame` for the briefing, `EndWorkerFrame` to end the session.

### How the pieces fit (the official Daily warm transfer example)

A `TransferCoordinator` frame processor owns the state: `TALKING_TO_CUSTOMER`, `HOLDING_CUSTOMER`, `TALKING_TO_AGENT`, `CONNECTED`, `TRANSFER_FAILED`. The LLM calls `initiate_warm_transfer` with a target and a summary. The coordinator waits until the hold message has been spoken (`BotStoppedSpeakingFrame`), enables hold music, gates the caller's audio, and calls `start_dialout`. On `on_dialout_answered` it takes the caller off hold and has the bot brief the human. A dial-out error, or `on_dialout_stopped` before the answer, takes the caller off hold, tells them the transfer failed, and returns to `TALKING_TO_CUSTOMER`. When the human hangs up after connecting, the bot ends the session.

### Pitfalls to check

- On Daily the bot owns the room: when it leaves, the room ends and the phone legs drop. In a warm transfer the bot stays as the audio bridge for the rest of the call, so check that it stops generating replies once the human is connected and that the session ends when the call does. The docs' note says a cold transfer that removes the bot entirely goes off Daily by SIP REFER.
- The official example briefs the human after the caller comes off hold, and its code comments that the customer also hears the briefing. A PR that copies the pattern must treat the summary as caller-visible, or brief before unholding.
- `on_dialout_stopped` means a finished call after connecting or a failure before the answer; the handler must branch on state.
- In the example, a participant leaving ends the session only in `TALKING_TO_CUSTOMER` or `CONNECTED`. Check what the PR does when the caller leaves while on hold or while the human's phone rings: the dial-out should stop.
- `TwilioFrameSerializer` has `auto_hang_up=True` by default: on `EndFrame` or `CancelFrame` it ends the Twilio call through the REST API (using `call_sid`, `account_sid`, `auth_token`). If the PR moves the same Twilio call into a conference and then ends the pipeline, check that this hang-up does not end the transferred call.
- The Twilio serializer works at 8000 Hz on the Twilio side (`twilio_sample_rate`); the pipeline may run at another rate.

## Vapi

- Transfers are a Transfer Call tool with a `transferPlan`. Vapi supports five traditional warm modes on Twilio calls: `warm-transfer-say-message`, `warm-transfer-say-summary` (a `summaryPlan` whose message includes `{{transcript}}`, with a 1 to 60 second timeout), `warm-transfer-twiml`, and two modes that wait for the operator to speak first (`timeout` 1 to 600 seconds, default 60).
- Assistant-based warm transfer: a transfer assistant calls the destination, talks with the operator, then calls `transferSuccessful` to connect or `transferCancel` to return the caller to the original assistant. `fallbackPlan` sets what the caller hears on failure and whether the call ends; `holdAudioUrl` sets hold audio; `maxDurationSeconds` (default 120) and `silenceTimeoutSeconds` (default 30) bound the operator conversation.
- Pitfalls: with `fallbackPlan.endCallEnabled` set to `true`, the caller cannot continue after a failed transfer. The transfer assistant's prompt must say to cancel on voicemail, IVR menus, hold queues, and declines; otherwise those get connected.
- Webhooks to your server authenticate with configured credentials (a Bearer token or HMAC).

## Retell

- The Transfer Call tool has three modes: cold (SIP INVITE by default, or SIP REFER), warm (the agent stays on the line and can wait for a real person, whisper to the destination, or make a three-way introduction), and agentic warm (a separate transfer agent talks to the destination and decides to bridge or cancel).
- Settings to check in review: the ring duration (it applies to all three modes), on-hold music, waiting for a real person when the destination queues calls (default wait 30 seconds), and, in agentic mode, the action on timeout: cancel the transfer, or bridge the caller anyway.
- Pitfalls: showing the caller's number to the destination needs caller ID override support from the telephony provider, and without it the transfer fails. Bridging on timeout connects the caller without a person having confirmed.
- Webhooks are signed: verify `X-Retell-Signature` with the API key over the raw request body.

## Sources

Twilio

- https://www.twilio.com/docs/voice/conference
- https://www.twilio.com/docs/voice/twiml/conference
- https://www.twilio.com/docs/voice/api/conference-participant-resource
- https://www.twilio.com/docs/voice/tutorials/warm-transfer
- https://www.twilio.com/docs/voice/api/call-resource
- https://www.twilio.com/docs/voice/tutorials/how-to-modify-calls-in-progress
- https://www.twilio.com/docs/voice/answering-machine-detection
- https://www.twilio.com/docs/voice/media-streams/websocket-messages
- https://www.twilio.com/docs/voice/twiml/connect/conversationrelay
- https://www.twilio.com/docs/voice/conversationrelay/websocket-messages
- https://www.twilio.com/docs/usage/webhooks/webhooks-security
- https://www.twilio.com/docs/usage/webhooks/webhooks-connection-overrides

LiveKit

- https://docs.livekit.io/telephony/features/transfers/warm
- https://docs.livekit.io/agents/prebuilt/tasks/warm-transfer
- https://docs.livekit.io/telephony/features/transfers/cold
- https://docs.livekit.io/reference/telephony/sip-api
- https://docs.livekit.io/reference/telephony/sip-participant
- https://docs.livekit.io/intro/basics/rooms-participants-tracks/participants
- https://docs.livekit.io/telephony/features/answering-machine-detection
- https://docs.livekit.io/intro/basics/rooms-participants-tracks/webhooks-events

Pipecat

- https://docs.pipecat.ai/pipecat/telephony/daily-pstn
- https://github.com/pipecat-ai/pipecat-examples/tree/main/phone-chatbot/daily-pstn-warm-transfer
- https://docs.pipecat.ai/api-reference/server/services/serializers/twilio

Vapi

- https://docs.vapi.ai/tools/transfer-call/warm-transfer
- https://docs.vapi.ai/calls/assistant-based-warm-transfer
- https://docs.vapi.ai/server-url/server-authentication

Retell

- https://docs.retellai.com/build/single-multi-prompt/transfer-call
- https://docs.retellai.com/features/secure-webhook
