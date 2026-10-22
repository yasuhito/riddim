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

## Unreported workers - limited stop observation implemented

- Evidence: the original notification scanner only classified actionable status
  reports. An empty status file stayed silent after endpoint death.
- Fix: reserved sequence 0 records one `unreported-stop` per generation after a
  positively observed live exact endpoint becomes recovery-grade dead or missing.
  Durable queue/ack receipts prevent repeat alerts. Status remains worker-owned.
- Validation: `test/unreported_stop_test.rb` covers launch ambiguity, unverified
  state, report suppression, progress, acknowledgement and replacement generations.
- Deliberately smaller than Firstmate `bin/fm-watch.sh`, `wedge_dead_record`:
  no native idle-as-done, pane hashing, wedge ladder or task-completion inference.
  Firstmate also monitors stable idle/turn-end episodes. Live-but-idle workers and
  workers dying before the first positive observation remain a follow-up, not claimed
  covered by this stop-only implementation.

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

## Delivery validation

- `bundle exec rake unit lint`: 238 tests, 413 assertions, no failures/errors/skips;
  RuboCop checked 111 files without offenses; Gherkin conventions passed.
- `bundle exec rake features`: 647 scenarios, 3780 steps passed.
- Real-Pi project auto-discovery startup passes with the guard; removing only
  that guard from the test's copied extension reproduces the lock collision and
  rejected positional brief. No source files need alteration for that control.
- Operational profile outside this worktree updated to
  `pi openai-codex/gpt-6.1-sol medium`. No ignored config was added to the commit.
