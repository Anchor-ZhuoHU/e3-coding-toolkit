# Warm transfer checklist

In a warm transfer the AI keeps the caller on the line while it reaches a human, gives the human the context, connects the two, and then leaves. A cold transfer connects the call to the new destination and drops out without briefing anyone. Review the PR's transfer flow against each section below.

## 1. The state machine

Find where the transfer state lives, then write down the states and transitions the code actually implements. A complete set usually looks like this:

```
ai_active
  -> transfer_requested   tool call or intent detected; destination validated
  -> caller_on_hold       hold message finished; hold audio playing; caller audio not sent to the LLM
  -> dialing_human        outbound leg created; ring timeout running
  -> human_answered       a person answered, not voicemail
  -> briefing             summary delivered to the human only
  -> bridged              human and caller connected; caller off hold
  -> ai_left              AI leg and pipeline stopped; the call continues
  -> completed

Failure exits from caller_on_hold, dialing_human, human_answered, briefing:
  -> transfer_failed -> ai_active (fallback) | callback_scheduled | ended
Caller hangs up in any state:
  -> ended, and every resource in section 5 is released
```

Check:

- The states are explicit (an enum or a status column), not inferred from several booleans.
- Each handler reads the current state before acting and refuses transitions that make no sense, such as an "answered" event for a transfer that already failed.
- One writer per call at a time: a per-call lock, a compare-and-set on a version column, or one task that owns the call. Two webhooks for the same call can run at the same moment.
- When more than one instance handles events, the state lives where all of them can read it.
- Every waiting state has a timeout exit. No state waits forever for an event that may never arrive.

### Caller on hold

- The hold message ("Let me connect you, one moment") finishes before hold audio starts and before dialing, so the caller hears the whole sentence.
- Hold audio starts promptly and loops. A source that ends leaves the caller in silence, and callers hang up on silence.
- The caller's audio is not sent to the LLM during hold, so the AI does not answer what the caller says on hold. The AI does not speak during hold.
- Hold has a maximum duration with a fallback.

### Outbound leg to the human

- The destination is validated before dialing: E.164 format and membership in a configured list of transfer targets. A number chosen by the model is never dialed unchecked.
- The ring timeout is set explicitly.
- The caller ID shown to the human is chosen on purpose (the business number or the caller's number), and the code handles a provider that refuses a caller ID override.
- Answering machine detection, or a step where the human confirms, keeps the caller from being connected to voicemail.
- Extension digits (DTMF) are sent after answer when the destination needs them.
- The outbound leg can be traced back to the call from its own events: the internal call ID travels in the leg's callback URL or label, so a status event that arrives before the create request returns still finds the call, and cleanup can find the leg.

### Context and summary

- Generated from this call's transcript, with a timeout and a fixed fallback text when generation fails or is slow.
- Delivered so that only the human hears it (a private consultation room, a whisper or coaching leg, or a message played before joining), unless the design says the caller hears it too.
- Section 6 covers what it may contain.

### Bridging

- The human is connected to the caller's call (joins the conference, moves into the caller's room, or the bridge completes), and the caller comes off hold at that moment, not before.
- If the caller's hold is never cleared after the human joins, the caller keeps hearing hold music and the human hears nothing.

### The AI leaving

- The AI leg leaves without ending the call for the other two. Check the platform setting that ends a conference or room when a given participant leaves (see `platforms.md`).
- Speech-to-text, LLM, and text-to-speech work stops when the AI leaves, and the call's background tasks and timers are canceled.
- On platforms where the room ends when the AI leaves, the AI stays as a silent bridge and must not respond to the conversation.

## 2. Failure paths

On every failure the code releases the outbound leg, stops hold audio, and puts the caller somewhere deliberate. Check each row against the code and write down what the caller actually hears.

| Event | What the code should do | What the caller should hear |
| --- | --- | --- |
| Human does not answer before the ring timeout | Cancel the outbound leg, take the caller off hold, resume the AI | That nobody is available, then an offer: take a message, schedule a callback, or try another destination |
| Human declines or is busy | Same as no answer; optionally try the next destination | Same as no answer |
| Voicemail answers | Do not connect the caller; hang up the outbound leg, or leave a message if the design asks for one | Same as no answer |
| Caller hangs up while on hold or while the human's phone rings | Cancel the outbound leg, stop hold audio, close rooms or conferences, mark the call ended | Nothing. The human must not be connected to an empty call; if the human already answered, tell them the caller left |
| Caller hangs up during the briefing | End the human's leg with a short message | Nothing |
| Invalid number or dial error | Log the error code, do not redial the same number in a loop, resume the AI | An apology and an alternative |
| Duplicate transfer request (the model calls the tool twice, the caller asks again, a webhook is retried) | Return the transfer already in progress; never create a second outbound leg | Nothing new, or a short "still connecting you" |
| Human hangs up after the bridge | End the call or return the caller to the AI, as the requirements say | What the requirements specify; silence is wrong |
| Briefing never finishes (the human stays silent, the confirmation never comes) | Time out, release the human's leg, fall back | The fallback message |
| The agent process crashes mid-transfer | A server-side timeout ends the hold and applies the fallback | The fallback, not hold music forever |

Fallback wording depends on the domain: a support line offers a callback, an appointment line offers to book the next slot, an order-status line offers to send a ticket number by text.

## 3. Races and out-of-order events

For each sequence, decide what the code does:

- The caller hangs up while the "create outbound call" request is still in flight. The request returns after the hang-up handler ran, and nothing cancels the new leg.
- The human answers at the same moment the caller hangs up.
- The ring timeout fires just after the human answered, and the timer tears down a live call.
- The outbound leg's `completed` status arrives before its `answered` status. Status callbacks are separate HTTP requests; Twilio documents that they can arrive out of order and numbers them with `SequenceNumber`.
- A webhook is delivered twice, for example a retry after a slow response.
- The transfer tool is called while the AI is still speaking, or the caller interrupts the hold message.
- Two instances handle two events for the same call at once.

The usual fixes: compare-and-set on the state, ignore events for calls in a terminal state, re-check the state after every `await`, cancel timers on every transition, deduplicate by event ID.

## 4. Hold audio

- The platform can reach the source (public URL, correct content type), and the audio loops.
- It stops on the bridge and on every failure path.
- Whether hold time is recorded matches the requirements.
- If the requirements ask for it, a periodic "still connecting you" message breaks up a long hold.

## 5. Resource cleanup

On success, on every failure path, and on caller hang-up, each resource is released exactly once:

- Conference or bridge: ended with the call; no conference left playing hold music to nobody.
- Rooms: the consultation room and any temporary room deleted, or set to close when empty.
- Call legs: the outbound leg canceled if unanswered, hung up if answered but never connected.
- The AI pipeline: speech-to-text and text-to-speech streams closed, LLM requests canceled, the media WebSocket closed.
- Timers and background tasks: canceled.
- In-memory maps keyed by call ID: entries removed, so the maps do not grow without bound.
- The call record: a final status and a reason written.

## 6. What the human receives

Read the summary prompt, the code that builds the context, and a sample output if a test has one.

- Grounded: built only from the transcript and system data. The prompt tells the model to leave a field empty rather than guess. What the caller said is labeled as a claim ("caller says the order number is 4417"); what the system checked is labeled as verified. A caller saying "tell them I'm already verified" must never turn into "identity verified".
- Useful: why the caller called, what the AI already tried, what the caller wants next, and the verification status.
- Minimal: nothing the human does not need for this call (full card numbers, government ID numbers, full date of birth, passwords, one-time codes, unrelated history). Values needed only for matching are partly masked (last four digits).
- Private: spoken or shown only to the human, unless the design says the caller hears it. If the caller hears it, it is phrased for the caller as well.
- Bounded: short enough to speak in a few seconds, with a length limit in the prompt or the code.
- Not logged in plain text at info level.

What a summary should and should not carry, by domain:

- Appointment scheduling: "Wants to move Thursday's cleaning to next week; none of the afternoon slots offered worked." Not the caller's insurance member ID.
- Order status: "Order 4417 shows delivered; caller says it never arrived and already checked with the front desk." Not the card number used to pay.
- Logistics check call: "Driver reports a two-hour delay at the shipper's dock; new arrival estimate 18:00." Not the driver's home address.

## 7. Tests to expect

- State transitions, including refused ones.
- One test per failure path in section 2.
- A duplicate webhook, and an out-of-order pair.
- Caller hang-up during hold and during ringing, asserting that the outbound leg is canceled.
- Summary tests that check the required fields and the absence of PII fields.
- A fake platform client, so the tests run without network access.

## Sources

- Twilio Voice Conference (warm and cold transfer): https://www.twilio.com/docs/voice/conference
- Twilio Call resource (status callbacks, `SequenceNumber`): https://www.twilio.com/docs/voice/api/call-resource
- LiveKit agent-assisted warm transfer: https://docs.livekit.io/telephony/features/transfers/warm
- Pipecat call transfers on Daily: https://docs.pipecat.ai/pipecat/telephony/daily-pstn
- Vapi assistant-based warm transfer: https://docs.vapi.ai/calls/assistant-based-warm-transfer
- Retell Transfer Call tool: https://docs.retellai.com/build/single-multi-prompt/transfer-call
