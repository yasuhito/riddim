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
- Full rerun: `bundle exec rake unit lint` passed 255 tests / 559 assertions with
  no failures, errors or skips; 113 Ruby files passed RuboCop and Gherkin conventions.
  `bundle exec rake features` passed all 647 scenarios / 3780 steps.
