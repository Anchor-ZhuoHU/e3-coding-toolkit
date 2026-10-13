# Example finding

One complete finding, written for a fictional PR that moves a clinic's appointment line to a new voice platform and adds warm transfer to the front desk. The file names, line numbers, and code are invented for the example.

---

#### F2. Caller hang-up while the front desk is ringing leaves the outbound call running

- Severity: High
- Label: must-fix
- Location: `app/voice/webhooks.py:142`, `app/voice/transfer.py:97`
- Scenario:
  1. The caller asks for a person. `TransferService.start()` puts the caller on hold, dials the front desk, stores `transfer.outbound_leg_id`, and sets the state to `dialing_human`.
  2. After 20 seconds on hold the caller hangs up. The status webhook for the caller's leg (`completed`) reaches `on_call_status()`.
  3. The front desk phone keeps ringing until the 30-second ring timeout. Someone answers at second 25; `on_human_answered()` joins them to the caller's conference, which is now empty, and marks the transfer `bridged`.

  Outcome: a receptionist answers into an empty conference, and the call record says `bridged`, so the transfer success rate counts a failed transfer as a success.
- Cause: the hang-up handler ends the call without looking at the transfer in progress, and the answer handler never checks that the caller is still there.

  ```python
  # app/voice/webhooks.py:140-143
  if event.status == "completed":
      call.state = CallState.ENDED
      store.save(call)
      return ok()
  ```

  ```python
  # app/voice/transfer.py:95-98
  def on_human_answered(self, call_id: str, leg_id: str) -> None:
      transfer = self.store.get_transfer(call_id)
      self.provider.join_conference(call_id, leg_id)
      transfer.state = TransferState.BRIDGED
  ```

- Fix:
  - In `on_call_status()`, when the caller's leg ends while the transfer is in `caller_on_hold`, `dialing_human`, or `briefing`, call a new `TransferService.abort(call_id, reason="caller_left")`. It cancels the outbound leg if it is still ringing, hangs it up if it was answered, stops hold audio, and sets the transfer to `failed` with that reason.
  - In `on_human_answered()`, re-read the call; if it is no longer active, hang up the human's leg (after a short "the caller has left" message, if the requirements want one) and skip the join.
  - Both handlers write the transfer with a compare-and-set on `transfer.version`, so a hang-up and an answer arriving together cannot both succeed.
- Test: `tests/voice/test_transfer.py::test_caller_hangup_while_human_ringing_cancels_outbound_leg`. With the PR's fake provider: start a transfer, deliver the caller's `completed` status, then deliver the human's `answered` event. Assert that `cancel_call` was called once with the outbound leg ID, that `join_conference` was never called, and that the transfer ends `failed` with reason `caller_left`. On the PR head the test fails: `cancel_call` is never called and `join_conference` is called once.

---

This is a finding and not a question because all three conditions hold: callers who give up on hold reach this path on every such call, both handlers were read in full, and the test reproduces the outcome against the PR's own code. It is High rather than Critical because the caller has already left; the damage is a wasted human call and a wrong metric, not a failed call for someone still on the line.
