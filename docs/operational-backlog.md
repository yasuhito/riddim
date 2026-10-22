# Operational failures and follow-ups

Record CLI failures here until resolved or transferred to an issue. Expected safety
refusals are not automatically bugs. Source-review's abandoned worktree is evidence
only and must remain untouched.

## Worker startup collision - fixed

- Evidence: `bundle exec ruby test/pi_worker_startup_test.rb` before the fix produced
  `watcher already bound to this home`, then `Agent is already processing` and exit 1.
  A real Pi process, loopback model, held supervisor lock and delayed session-start
  callback pin the adverse ordering before the positional task brief.
- Cause: task launch exports `RIDDIM_ACTOR=branch` and the shared state home;
  the project extension registered supervisor callbacks even in workers.
- Fix: nonempty actor markers disable supervisor callbacks and repair commands.
  Unknown markers fail closed, matching the existing operator boundary.
- Validation: the same reproduction passes after the fix. No lock weakening or
  extension-disable workaround is required. Full suite results recorded at delivery.

## Unreported workers - stable live-idle and stop attention implemented

- Evidence: source-review was Pi alive but idle without a report. The original
  scanner only classified actionable status reports. Initial commit `af0ad38`
  added endpoint-death detection but explicitly left this original symptom
  uncovered; review reopened the task rather than treating stop-only as sufficient.
- Live-idle reproduction: `bundle exec ruby test/unreported_idle_test.rb` initially
  failed six checks, including alive+idle+no-report and busy-transition behavior.
- Firstmate `bin/fm-watch.sh`'s pane-staleness backbone requires repeated identical
  captures and non-busy state, surfaces inconclusive nonterminal stale for inspection,
  and clears pending stability when output or activity changes. Riddim implements
  the stricter Pi-only subset: positively verified native idle plus three unchanged
  nonempty captures at least five seconds apart and a thirty-second launch grace
  from first liveness. Busy/unverifiable observations, capture failures, output
  changes, clock rollback and sampling gaps over ten seconds reset stability.
- Reserved sequence 0 records one `unreported-idle` or `unreported-stop` per exact
  generation/endpoint record, sharing one durable attention slot. Acknowledgement
  suppresses duplicates after restart or busy/idle transitions. Worker reports
  keep independent IDs and status files remain exclusively Worker-owned.
- Tests: deterministic scanner regressions cover the original symptom, launch
  grace, busy transitions, observation gaps, capture failures, metadata replacement
  and deduplication. The real extension/watcher test exercises busy-to-idle reset
  and an independent subsequent report. A real Pi plus loopback model consumes
  the live-idle follow-up without a Worker report (native backend state is a
  controlled fixture, not a second managed worker).
- Still smaller than Firstmate: no wedge ladder, inferred completion, recurring
  idle episodes within one generation, or alerts for death before first positive
  liveness observation. Attention requests inspection, never restart/cleanup.

## sol-repair teardown refusal - reproduced and fixed

- Incident evidence: `/tmp/riddim-teardown-sol-repair-incident.md`. Approved commit
  `0812560b3cf22591b2b6628b98e4e3bef1d775ae` landed on local main and the
  worker worktree was clean, but teardown refused
  `a different agent occupies the exact pane; retaining assets`.
- Read-only real-Herdr reproduction from the teardown-fix worktree:
  `bundle exec ruby -Ilib -rriddim/ownership -rriddim/teardown -e 'endpoint = Riddim::Ownership::Endpoint.resolve("sol-repair"); Riddim::Teardown.verify_agent!("sol-repair", endpoint)'`
  produces that exact refusal. No teardown, close, rename, or worker mutation
  was attempted. The original worker remains evidence.
- Herdr 0.9.5 `agent get w13E:p1` in session `default` reports Pi at the
  recorded workspace `w13E` and tab `w13E:t1`, with both cwd fields matching
  `/home/yasuhito/Work/riddim-riddim-sol-repair`, but neither `name` nor
  `agent_session`. Herdr's `src/api/schema/agents.rs`, `AgentInfo`, declares
  both fields optional and omits absent values. A missing name is not proof
  of a different occupant. Herdr names are mutable live-occupant aliases,
  not durable task or process-incarnation identifiers.
- `pane process-info` independently confirms a foreground Pi, but neither
  that observation nor matching cwd proves it is the original task's Pi.
  The retained record has a spawn generation and exact endpoint, but no
  recorded Pi session or process-incarnation binding. This evidence cannot
  distinguish the original unnamed Pi from an unnamed replacement in the
  same pane and worktree.
- Firstmate `bin/fm-backend.sh`, `fm_backend_validate_task_endpoint`, binds
  task identity to durable metadata before cleanup; `bin/fm-teardown.sh`
  separately validates the spawn incarnation. Its Herdr close path in
  `bin/backends/herdr.sh`, `fm_backend_herdr_kill_serialized`, closes only
  that recorded pane and confirms disappearance before record retirement.
  It does not require an agent alias. Its teardown comments explicitly say
  cwd is incidental and cannot veto cleanup of the recorded endpoint.
- Resolution: human selected Firstmate-compatible ownership of the durable,
  generation-locked exact endpoint, not proof of the original Pi process
  incarnation. Teardown no longer treats optional mutable aliases as ownership.
  It still requires Pi at the recorded pane/workspace/tab in the recorded
  session, and now rechecks the generation, endpoint and complete record bytes
  after backend probes immediately before close, under the existing name lock.
  Cwd and Pi-session metadata do not replace or veto the durable binding.
- Before the fix, three actual-shape/alias/cwd cases failed with the original
  refusal. Three concurrent record-change cases exposed a second gap: teardown
  detected the change only after closing the pane. Both sets now pass. The
  captured Herdr response is retained in
  `features/fixtures/herdr/unnamed_pi.json`; feature tests adapt only endpoint
  IDs before testing acceptance and foreign/missing identity refusals.
- All 39 teardown scenarios / 565 steps pass, including existing self-pane,
  clean+landed, name-lock and unconfirmed-disappearance safeguards. The updated
  live read-only `verify_agent!(endpoint)` check passes between two durable
  ownership rechecks against sol-repair. No close or actual retirement was
  attempted; that still requires separate authorization.
- Full delivery validation: `bundle exec rake test lint` passes 262 unit tests /
  583 assertions and 661 feature scenarios / 3990 steps. RuboCop checks 117
  files without offenses; Gherkin conventions pass.

## sol-repair registration unconfirmed - unresolved observation

- Supervisor evidence: start returned `Pi registration could not be confirmed`,
  while later peek showed Sol medium working and agent-state alive.
- This particular launch disabled automatic extensions to bypass the startup
  collision. Missing extension-provided registration may be workaround-caused;
  no independent registration bug is established by that evidence.
- Next: reproduce a normal extension-enabled launch after the role fix and check
  exact session registration. Do not restart or discard this worker to test it.

## source-review exit refused - expected safety, recovery UX follow-up

- Supervisor evidence: pending composer text after interrupt caused exit refusal;
  a human had to clear it.
- Refusing to type destructive commands into an occupied composer is intentional.
  It is not a confirmed exit bug. Evaluate clearer recovery guidance separately;
  never auto-clear human text as a repair.

## Supervisor observer starvation - reproduced and fixed; original incident uncertain

- Supervisor evidence after sol-repair start: failure notification, home identity
  `56:803419564`, lock identity `56:1105737935` unchanged, scan empty, recovery
  unconfirmed. These observations do not establish a healthy live watcher.
- Worker-lock collision is independently reproduced above. It does not explain
  the original supervisor observer's failure: a refused second observer cannot
  steal the existing flock. Unchanged inode identities prove neither process
  liveness nor heartbeats. Need the original failure reason/process evidence.
- Independent real-Pi reproduction: holding `.meta-worker.lock` for six seconds
  after observer readiness produces `watcher heartbeat stale; ownership unverified`.
  Launch holds that lock through registration. The scanner's blocking lock acquire
  starved heartbeat production. This matches the original timing and unchanged
  inode observations, but the original generic follow-up omitted its precise cause;
  the available supervisor transcript cannot prove which failure fired then.
  Failure follow-ups now include the reason so later incidents preserve it in
  the supervisor transcript rather than only transient UI/stderr.
- Fix: background scans and presentation skip locked workers and revisit them on
  later polls; manual scans still block. Regression:
  `test/pi_notifications_e2e_test.rb`, `test_busy_worker_lock_does_not_kill_supervisor_watcher`.
- Firstmate `.pi/extensions/fm-primary-pi-watch.ts` and
  `docs/watcher-continuity.md` use lock-checked bounded exponential recovery.
  Riddim now retries unexpected exits/stale heartbeats of a verified observer up
  to three times per session, against the original home/lock identities. It waits
  for child retirement and fresh readiness; shutdown cancels scheduled retries.
  It never steals a competing live lock or silently rebinds changed ownership.
  Exhaustion or ambiguity emits one alarm. Explicit repair resets the budget.
- Real-Pi regressions cover watchdog recovery, three refused retries, changed lock
  refusal, and launch-lock heartbeat continuity. A failed successor during pending
  report handling still alerts immediately rather than withholding the report;
  extending bounded recovery to that path remains a scoped follow-up.

## Validation follow-up - linked-worktree default-path assertion

- First full validation: unit tests passed; feature validation exceeded the initial
  command deadline. Rerun completed 647 scenarios with one assertion failure:
  default supervisor state was expected under this checkout, but the worker's
  Git-admin `riddim-home` marker correctly selected the operational state home.
- This was a test expectation bug, not a CLI routing failure. The feature now
  accounts for the same validated linked-worktree marker as the CLI. No operational
  state marker was changed or removed to make the test pass.

## Initial delivery validation (`af0ad38`)

- `bundle exec rake unit lint`: 238 tests, 413 assertions, no failures/errors/skips;
  RuboCop checked 111 files without offenses; Gherkin conventions passed.
- `bundle exec rake features`: 647 scenarios, 3780 steps passed.
- Real-Pi project auto-discovery startup passes with the guard; removing only
  that guard from the test's copied extension reproduces the lock collision and
  rejected positional brief. No source files need alteration for that control.
- Operational profile outside this worktree updated to
  `pi openai-codex/gpt-6.1-sol medium`. No ignored config was added to the commit.

## Live-idle regression validation - fixture failure resolved

- During the new integration test, the watcher correctly refused `status file has
  no final newline`. The test fixture had appended literal `\\n` instead of a
  newline while simulating a subsequent report. Fixed the fixture; this was an
  expected malformed-status refusal, not a production report-writing bug.
- Live-idle end-to-end check: real Pi consumed the alert after launch grace with
  no Worker report or completion claim. Native liveness/pane state was injected at
  the Herdr observation seam; Pi, the extension, Ruby observer and local model
  transport were real.
- Rerun at `7fbbc65`: `bundle exec rake unit lint` passed 255 tests / 559 assertions with
  no failures, errors or skips; 113 Ruby files passed RuboCop and Gherkin conventions.
  `bundle exec rake features` passed all 647 scenarios / 3780 steps.

## Slow/hung Herdr observation - reproduced and fixed after review

- Review initially identified an unconfirmed risk: Herdr captures ran synchronously
  inside the name lock, while watcher beats followed the scan. Per-call timeouts
  alone would not bound cumulative multiworker probes.
- Real-Pi fault reproduction: `test_hung_herdr_does_not_block_worker_report_progress`
  failed because a sixty-second fake Herdr subprocess kept the real report CLI
  waiting on the worker lock past one second. The fake executable runs through
  actual `Herdr.capture` / Open3, not a scanner-side sleep.
- Multiworker reproduction: five records with three 0.4-second captures each caused
  `test_cumulative_slow_herdr_probes_do_not_starve_heartbeat_or_recovery_budget` to
  return `Riddim watcher FAILED; inspect pending notifications` instead of ready.
  This independently confirms cumulative backend work can exhaust heartbeat grace.
- Fix: one shared 500 ms monotonic Herdr-I/O budget per activity scan, across all
  workers and all nested captures. Deadline-scoped Open3 children own process
  groups; timeout kills the group and joins readers before Open3 waits. Normal
  non-observation commands retain their original capture behavior and routing.
- Timeout is unknown evidence and clears pending idle stability, never a stop or
  completion. Exhausting the budget skips remaining probes, not report/status
  reconciliation. A worker report can wait for at most the remaining backend
  budget plus local scan/publication work, not an unbounded Herdr read.
- The watcher rotates the next activity scan after the last attempted worker so
  a slow first record cannot monopolize every budget. The real-Pi regression also
  checks progress to two different worker observation markers without restarting
  the observer or consuming recovery attempts.
- Firstmate `bin/fm-watch.sh`, `watcher_capture` / `fm_active_check_stop`, owns and
  retires capture process groups even for blocked reads. Riddim keeps that
  subprocess ownership contract and adds a shared short deadline appropriate to
  its four-second heartbeat grace; it does not copy Firstmate's broader watcher.
- During fixture setup, an inherited-Bundler report subprocess initially exited 1
  before the intended lock assertion, without retained diagnostics. The fixture
  now launches it unbundled and retains stderr. The intended lock-blocking failure
  was then independently reproduced; no separate production CLI cause is claimed.

## Idle sampling jitter - reproduced and fixed after review

- `test_scan_start_and_per_worker_clock_jitter_does_not_prevent_attention` used
  samples at 100, 105.1, 110.0, 115.2, 120.1, 125.3 and 130.2 seconds. It failed
  with no alert: a slightly early sample was discarded, then the next looked like
  a gap over ten seconds and reset stability indefinitely.
- Fix: retain `last_observed` separately from `last_sample`. A verified capture
  arriving before the five-second counting boundary preserves continuity without
  counting as another stable sample. Actual observation gaps still reset after
  ten seconds, and launch grace still measures real observed elapsed time.
- Existing counted-only private candidates migrate conservatively using their last
  counted sample as the last known observation. Tests cover legacy data and a
  timed-out backend resetting stability, as well as the original jitter sequence.

## Intentional exit without a report - expected attention

- While a current local-only record remains, an intentional Pi exit without an
  actionable report can produce the same `unreported-stop` observation as an
  unexpected exit. This is intentional inspection attention, not a failure or
  cleanup authorization. Removing/retiring a record remains a separate locked
  lifecycle action. No safety behavior was weakened to suppress this case.

## Shared-budget and jitter delivery validation

- `bundle exec rake unit lint`: 262 tests / 583 assertions passed, with no failures,
  errors or skips; 117 Ruby files passed RuboCop and Gherkin conventions passed.
- `bundle exec rake features`: 647 scenarios / 3780 steps passed.
- Real-Pi fault regressions now preserve heartbeat with cumulative slow multiworker
  calls and allow a real report to complete during a hung Herdr probe. Dedicated
  capture tests cover a shared deadline, routing/context restoration, and a child
  that exits while a descendant retains an output pipe.
- Deliberate limit: deferred or timed-out probes do not prove worker state. Large
  or persistently slow fleets can delay attention; an observation gap still resets
  stable-idle evidence rather than inventing continuity. Reports remain independent
  of that observational uncertainty.
