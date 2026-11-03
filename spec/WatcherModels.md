# Watcher fix models: AckMarkerRace and HeartbeatWatchdog

Two small PlusCal models check the two watcher fixes recorded in
[`docs/operational-backlog.md`](../docs/operational-backlog.md). They are separate
from [`NotificationHandoff`](NotificationHandoff.md), which models neither ACK nor
heartbeat. `bundle exec rake model` translates and checks them with the other four
models. Neither model claims the cause of the 2026-11-02 incidents, refinement of
Ruby, JavaScript, Node or Linux, or behavior outside its stated bounds.

## AckMarkerRace

One presented row, one `riddim notifications ack` and one watcher poll of
`Notifications.pending` for the same task. The poll is **not** atomic: listing,
each marker read and each `marker?` existence check and read are separate steps,
because the original bug lived between them. 36 distinct states, depth 16.

| Model step | Implementation |
|---|---|
| `AckLock` / `AckUnlock` | `Notifications.acknowledge`: `Ownership.with_lock(match[1])` |
| `PublishIntent`, `PublishHandled`, `UnlinkIntent` | `publish(intent)`, `publish(handled)`, `File.unlink(intent)` |
| `ReaderLock` (acquire, or defer while ACK holds it) | `pending`: `Ownership.with_lock(task, wait:)`; the watcher passes `wait: false`, which skips a busy task |
| `List` | `pending_for`: `task_files(task)` |
| `VerifyMarkers` | `verify_marker_queue` per listed marker; a vanished file is the observed ENOENT |
| `HandledExists`/`HandledRead`, `IntentExists`/`IntentRead`, `Decide` | `handled?`: `marker?(handled) && !marker?(ack-pending)`, each an existence check then a read |

- `NoObserverError`: a legitimate concurrent ACK never makes the poll fail.
- `NoInventedHandling`: the row is omitted as handled only with the receipt durable
  and the intent withdrawn. Pending again (replay) and deferral are allowed.
- `QueueRetained`: the queue row is never removed.
- `ReaderFinishes`: with weak fairness for both processes, the poll ends.

## HeartbeatWatchdog

Discrete seconds with `Interval = 1` (`WATCHDOG_INTERVAL`) and `Grace = 4`
(`BEAT_TIMEOUT`). Pi suspends at most `MaxStalls = 2` times for up to
`MaxStall = 6` seconds each, at any point, including inside a frame's I/O
callback. A healthy watcher beats once per second into a pipe holding up to two
frames. The watcher may die at most once, no later than
`Horizon - (Grace + 2 * Interval + MaxStalls * MaxStall)` with `Horizon = 24`.
128,076 distinct states, depth 75.

| Model step | Implementation (`.pi/extensions/riddim-notifications.ts`, `startArm`) |
|---|---|
| `Advance` | Time passes while Pi is suspended, or when running Pi has no due tick and no readable frame; a healthy watcher's beat enters the pipe |
| `Suspend` | Swap-in, GC or synchronous work stopping Pi's event loop |
| `Frame` | `proc.stdout` `data` for `ready`/`beat`: `fresh()` sets `verifiedAt` and `lastTick`, clears `piStalled` |
| `Tick` | The `setInterval` watchdog: adds `max(0, now - lastTick - WATCHDOG_INTERVAL)` to `piStalled`, then `SIGKILL` if `silence - piStalled > BEAT_TIMEOUT` |
| `Die` | A watcher that stops writing frames |

When Pi resumes, `Frame` and `Tick` can both be enabled, and TLC explores both
orders. `sinceFrame` is specification history: the number of seconds Pi could run
since the last handled frame.

- `NoFalseKill`: a watcher is killed only if it died.
- `PromptDetection`: a dead watcher with an empty pipe is killed within
  `Grace + Interval` seconds of Pi running time after the last frame. An earlier
  stall is never credited to silence after a fresh frame.
- `Detected`: with weak fairness for time, frames and ticks (Pi always resumes
  within `MaxStall`), a dead watcher is eventually killed.

Recovery budget, home/lock identity checks, readiness timeouts, the watcher's
scan duration and a stall shared by the watcher (system-wide) are outside this
model. The real-Pi tests cover recovery and identity.

## Negative controls and their real reproductions

Mutated copies outside the checkout are retranslated with `pcal.trans` and checked
by TLC. None of these mutations is committed.

| Mutation | TLC result | Matching implementation regression |
|---|---|---|
| Reader without the name lock (original `pending`) | `NoObserverError`: ACK publishes intent and receipt, the reader lists the intent, ACK unlinks it, the read fails | `NotificationAckRaceTest`, which pauses real CLI processes in that order |
| ACK without the name lock | `NoObserverError` | Not an implementation state |
| Unlocked reader that ignores missing files and the intent | `NoInventedHandling` | Not an implementation state |
| Kill on `now - verifiedAt > Grace` (original watchdog) | `NoFalseKill`: Pi suspended while frames queue, the late tick runs first | `test_stalled_pi_host_does_not_kill_a_beating_watcher` (`SIGSTOP` of real Pi) |
| `Frame` keeps `lastTick` (first stall fix) | `PromptDetection`: the frame is handled before the late tick, the tick credits the earlier stall, detection takes six running seconds | `test_pi_stall_before_a_frame_neither_kills_nor_shields_the_watcher` (12.0 s measured before the fix) |
| Tick never kills | `Detected` violated | Not an implementation state |

The witnesses `outcome # "handled"` and `~killed` are both violated, so the
committed models reach handling and a kill.
