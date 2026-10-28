# Notification handoff in one reused factory

`NotificationHandoff.tla` checks one narrow race in Riddim's notification
extension. A pending delivery from internal epoch A settles after shutdown and
restart have installed epoch B's bookkeeping in the **same factory closure**.
A and B are implementation epoch labels, not Pi session IDs or extension runtime
versions. Public terminology is defined in [`CONTEXT.md`](../CONTEXT.md).

```text
Human -> Riddim session (supervisor Pi conversation) -> coordinates Workers
                    |
                    +-> Riddim notification extension in an extension runtime
                              |
                              +-> notification watcher processes -> durable report rows
Reload: pre-reload extension runtime -> shutdown -> replacement runtime -> start
        Riddim session may stay the same; Worker generation stays independent.
```

## What TLC checks

Run `bundle exec rake model` with the existing pinned Java/jar described in
[`README.md`](README.md). The explicit task translates PlusCal and runs all four
models, outside default rake/CI. Do not edit the generated translation.

The bound is one reused factory, one shutdown/start handoff, two ordinary reports
from one Worker generation, one fixed source home/lock pair, and one outstanding
A delivery. A resolves or rejects at any enabled interleaving, including before
shutdown, during the inactive interval, during B delivery, and after B shutdown.
B's two deliveries succeed; their completion steps are separate from their offers.
Normal TLC exploration has 138 generated / 104 distinct states, depth 12, no
remaining states and no violations (one worker, breadth-first search).

- `TypeOK` checks the finite domains and ready-child association.
- `LatePredecessorIsolated` is an action property: stale `SettleA` must preserve
  accepted IDs, child/readiness bookkeeping and failure count. It must also leave
  B's `inFlight` untouched. Clearing an old A flight is permitted: shutdown does
  not reset `inFlight` in the implementation.
- `UnhandledRecoverable` checks that every modeled published row remains in the
  unhandled queue. It does not assert eventual delivery or handling. No action in
  this scenario is authorized to acknowledge a report.

There is **no fairness assumption** and no liveness property. Infinite stuttering
is allowed; PlusCal's generated `Termination` formula is not configured for checking.
`trace` and `published` are specification history, not production state.

## Independent identities

| Layer | Implementation | Model treatment |
|---|---|---|
| Riddim session | Pi's durable conversation/session ID; `initialize` reads it only for scheduled routing | Not varied; not A/B |
| Extension runtime | Pi loads a replacement factory/runtime on real reload | Same-factory reuse is the synthetic seam, not actual reload |
| Internal callback epoch | Factory-local `serial`, captured `epoch`, `active` | `serial = A/B/retired`, `active` |
| Notification watcher process | `proc`, `child`, `readyChild`; fresh random `nonce` per `startArm` | Distinct process symbols, never reused; valid nonce/frame binding assumed |
| Filesystem source | `homeIdentity()` plus `lockIdentity()` (device/inode); source-keyed accepted sets | One fixed verified pair; `accepted` abbreviates that one map entry |
| Worker report | `worker.<spawn_gen>.<sequence>` | Integers 1 and 2 abbreviate two exact IDs in the same Worker generation |

`serial` starts at zero for a fresh factory and increments at shutdown. It is
not a monotonic counter across module reload, a software version, a watcher nonce,
or a Worker generation. None of these identity checks proves the other layers.

## Operations and implementation correspondence

All extension references below are to
[`.pi/extensions/riddim-notifications.ts`](../.pi/extensions/riddim-notifications.ts).
Each PlusCal label is atomic. Several labels deliberately compress successful
readiness/delivery prefixes; they are not claims that these asynchronous prefixes
are indivisible in JavaScript.

| Model action/state | Exact implementation operation or guard | Fixture action/evidence |
|---|---|---|
| Initial `rows = {1}` | `Notifications.classify` publishes `.notifications/<id>.json`; `present` publishes `.presented-<id>.json` | Append first status line, real watcher scans before first follow-up |
| `OfferA`, `OfferB1`, `OfferB2` | `deliver(epoch)` enters only if `inFlight !== epoch && active && serial === epoch`; inserts accepted IDs, awaits `arm()`, rechecks active/epoch and source, captures `successor`, calls `sendUserMessage(..., {deliverAs: "followUp"})` | `fakePi.sendUserMessage` observes the exact report ID; A returns a controllable promise, B returns void |
| `ShutdownA`, `ShutdownB` | `session_shutdown` sets inactive, increments serial, retires child, clears child/readiness, bindings, accepted sets and batches; leaves old `inFlight` alone | Await the registered shutdown handler |
| `StartB` | `session_start` -> `initialize` -> active and `arm()` | Reuse `old` as `successor` and invoke start; observed follow-up confirms subsequent successful readiness |
| `WaitA`, `SettleA` rejection | `deliver` catch's `if (serial !== epoch) return`; deletes accepted IDs only for current epoch; `successor && child === successor` guards readiness withdrawal/process signal; `failure` independently checks `active`/serial | Reject A only after B has reoffered ID 1; existing assertions require no new message/notice and no later duplicate ID 1 |
| `SettleA` resolution; `FinishB1/2` | `deliver` finally's `if (inFlight === epoch) inFlight = null`; loop/re-entry require current active epoch | A resolution is explored by TLC, not injected by this selected fixture; B's void return settles immediately |
| `Publish2` | Second status append followed by `Notifications.scan/classify` queue publication | Append second line and wait for ID 2; the append checkpoint precedes the hidden real scan |
| `rows`, `handled` | `Notifications.pending` filters queue rows with `handled?`: matching `.handled-<id>.json` and no matching `.ack-pending-<id>.json` | Ruby driver rescans after shutdown and requires both exact IDs still pending |

The notification watcher process is real, not a modeled stub:
[`Watcher.run/observe`](../lib/riddim/watcher.rb) holds directory and marker flocks
for its lifetime, scans through `/proc/self/fd`, verifies ownership before and
after scan, and emits ready/pending with nonce and identity. `startArm` checks the
nonce and captured epoch/process on stdout; it accepts pending only after ready
and with the bound home/lock. After readiness it checks a live child and current
filesystem identity. On pending close it queues a batch and calls `deliver`.
This model assumes those checks succeeded; it does not prove the flock, nonce,
readiness or filesystem protocol.

### Persistence is not acceptance

`rows` denotes durable queue files, not Pi's message queue. `published` denotes
completed classification. `Publish2` groups status append plus completed scan;
intermediate status-only and crash states are excluded. The fixture checkpoint
at append is only an observable projection of this macro, not proof of its atomicity.
`Notifications.classify` publishes queue rows before replacing the cursor. `present`
adds a presentation marker, not a receipt of human handling. `acknowledge` explicitly
requires that marker and writes ACK intent/handled receipts while retaining the
queue row. No ACK call, handling action, or crash-recovery protocol is modeled here.

`accepted` is factory-local suppression cleared at shutdown, populated **before** follow-up acceptance
while arming the next notification watcher process. It is not proof Pi accepted,
consumed or handled a message. Shutdown clears it; restart can replay every
unhandled row. The fixture's two status lines and Ruby's post-shutdown scan check
retention independently of the in-memory bookkeeping.

## Accepted observation and rejected transition

The selected test is
`NotificationSessionRaceTest#test_late_predecessor_rejection_cannot_claim_successor_or_lose_later_report`,
driving [`notification_session_race.mts`](../test/support/notification_session_race.mts).
Its scenario-specific JSON projection is:

```text
OfferA, ShutdownA, StartB, OfferB1, RejectA, Publish2, OfferB2, ShutdownB
```

A offers ID 1, B reoffers it after shutdown clears suppression, stale A rejection
leaves B alone, and B offers ID 2 without another ID 1. Both rows remain pending.
`RejectA` records rejection injection plus the fixture's existing bounded assertions,
not an instrumented internal callback. `StartB` is invocation, not a ready-frame
observation. `FinishB1/2`, scans and accepted-map changes are hidden.

An external TLC witness check adds `ObservedNotReached == trace # <<...>>` using
the actual JSON output and asks TLC to refute it. TLC reaches that exact projection
while the normal safety checks remain enabled. This is trace-level compatibility
of one sampled run and the stated macro abstraction, **not a refinement proof**
for all executions. The fixture does not expose internal accepted/inFlight state;
its no-duplicate and later-delivery assertions are indirect evidence.

The rejected model transition is `OfferB1; SettleA(reject)` with `serial = B`:
`accepted = {1}` must not become `{}`. In an external disposable copy only, remove
`/\ serial = "A"` from the PlusCal rejection condition, regenerate with `pcal.trans`,
and TLC reports `LatePredecessorIsolated` at that transition (31 distinct states
before stopping). The model retains the independent process and failure guards.

In a separate implementation copy, remove only catch's
`if (serial !== epoch) return;`. The same regression reports
`old callback must not remove the successor's accepted identity`, `3 !== 2`.
ID 1 is repeated when ID 2 causes rearming after A deleted B's suppression entry.
The existing independent process-identity/failure guards remain intact. No real
product bug was repaired by removing this negative mutation; the production
extension is unchanged. Fixture shutdown now runs in `finally` so an assertion
failure also retires its owned notification watcher process.

## Real reload is separate evidence

Pi 1.4.0's installed `docs/extensions.md` ("Add it to Pi" and "Understand the
runtime lifecycle") states reload replaces the extension runtime, with
`session_shutdown -> load replacement extension runtime -> session_start`.
Its `docs/sessions.md` defines a session as a conversation. Read at
`/home/yasuhito/.pi/agent/install/releases/1.4.0/node_modules/@earendil-works/pi-coding-agent/`;
external evidence retains those files and their hashes.

Pinned upstream sources:

- [AgentSession.reload and _bindExtensionCore, v1.4.0](https://github.com/earendil-works/pi/blob/v1.4.0/packages/coding-agent/src/core/agent-session.ts): await shutdown, invalidate old runner, reload resources, build replacement runtime, emit start. The bound `sendUserMessage` is fire-and-forget and routes errors to the runner; the fixture's rejectable promise is a deliberately stricter synthetic seam, not the normal Pi API return contract.
- [Resource loader, v1.4.0](https://github.com/earendil-works/pi/blob/v1.4.0/packages/coding-agent/src/core/resource-loader.ts): clear extension cache and load replacement extensions.
- [Extension loader, v1.4.0](https://github.com/earendil-works/pi/blob/v1.4.0/packages/coding-agent/src/core/extensions/loader.ts): create the runtime and invoke extension factories.

[`PiNotificationsReloadTest`](../test/pi_notifications_reload_test.rb) separately
uses actual interactive Pi, a disposable session, fake Herdr and a loopback
provider. Its exhausted-recovery/reload test checks a different runtime identity,
shutdown-before-start, unchanged source identities and replay of unhandled IDs.
Its scheduled test checks unchanged Pi session ID across reload without implicit
ACK. The race fixture alone proves none of those real-reload facts. These tests
also do not inject A's rejected promise across actual reload; that correspondence
remains unproved.

## Assumptions and exclusions

The source home/lock identities remain fixed and private; no non-cooperating writer,
identity reuse, report corruption, process-ID reuse, or source replacement occurs.
Successful readiness prefixes and shutdown completion are macro steps. There is no
modeled timeout, heartbeat, failed B delivery, watcher recovery, startup failure,
shutdown timeout, overlap inside shutdown, or more than one factory handoff.
Separate existing source-replacement/timeout fixtures exercise some excluded paths.
Scheduled prompts, recipient routing, sequence 0 attention, ACK races, actual human
handling and filesystem crash durability are outside this model.

TLC proves only the configured finite abstraction. It does not prove JavaScript,
Ruby, Pi or OS refinement, global liveness, end-to-end exactly-once delivery, or
exactly-once human/task side effects. Neither a report nor notification reception
is Git readiness or landing/publication/destruction approval.
