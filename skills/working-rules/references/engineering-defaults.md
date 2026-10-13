# Engineering defaults

Stack-agnostic defaults that come from real review findings. The repository's own conventions win where
they differ; note the difference in the design doc or the review.

## Backend and integrations

- Never hold a database transaction open across an external call: commit or close first, then call.
- One retry layer: when a workflow or a queue retries, turn the SDK's own retries off. Stacked retries
  multiply the timeouts.
- An overall deadline around each external call. SDK timeouts are per phase (connect, each read), so a
  server that trickles bytes never trips them. Keep the job's own time limit above that deadline.
- State changes are conditional updates checked by row count (`UPDATE ... WHERE status = 'draft'`), not
  read, check, write: a retry or a concurrent request cannot apply the change twice.
- Webhooks and callbacks are delivered at least once and not always in order: deduplicate by the event's
  id, and ignore an event that would move a record backwards in its state machine.
- Never log user payloads: log counts, timings and ids, and pass ids, not data, through queues and
  workflow history.
- Validate configuration at startup, so a bad value stops the process instead of failing every request
  that uses it.

## LLM steps

- Store the model name and the prompt version with each output; bump the version whenever the prompt
  changes.
- Verify each quote mechanically (an exact substring) against the input the model actually received,
  after any transform such as speech to text, not against the text you started from.
- Structured output: a forced tool call or a JSON schema with a flat, hand-written shape. Generated
  schemas carry `$defs` and `$ref`, which providers support unevenly.
- Temperature 0 and a pinned model for anything that is compared over time (evaluations, regression
  checks), and a cache keyed by model, prompt version and input.
- Keep a small hand-written case set and run it whenever the prompt or the model changes.

## Frontend

- `fetch` rejects only when there is no response: check `res.ok`.
- Poll with a `setTimeout` chain, not `setInterval`: the next request waits for the previous answer.
- Disable inputs while a save is in flight: the reset after the save wipes whatever was typed meanwhile.
- Conditionally rendered tabs unmount and lose their input: keep both mounted and hide the inactive one.
