Feature: Inspect durable actionable reports from the selected local-only home

  Background:
    Given a local Git project for worktree start
    And the project checkout is on main
    And a config directory with agent profile:
      """
      pi openrouter/z-ai/glm-5.3-flash max
      """
    And Herdr starts the agent only in the linked worktree
    And a fake Pi executable is on PATH for the task launch
    And a task file containing:
      """
      Work in the local-only branch.
      """
    And a local-only task was started

  Scenario: Only one watcher can bind the selected home
    When a notification watcher is armed
    Then another watcher fails to arm without claiming readiness

  Scenario: A watcher publishes, wakes, and a successor stays live for later reports
    When a notification watcher is armed
    And the worker reports "done [at=1]: first claim"
    And the watcher reports a pending notification without changing the worker
    When a successor watcher is armed excluding the first report
    And I acknowledge the first worker notification
    And the worker reports "blocked [at=2]: second claim"
    Then the successor reports only the new notification

  Scenario: Reconcile a masked actionable event and distinct later claims after downtime
    Given the worker reports "needs-decision [at=1]: choose A"
    And the worker reports "working [at=2]: thinking"
    And the worker reports "blocked [at=3]: waiting"
    And the worker reports "done [at=4]: claim"
    When I scan pending notifications twice
    Then pending notifications retain three separate report identities without changing the worker

  Scenario: An actionable event after an earlier routine scan is retained
    Given the worker reports "working [at=1]: progress"
    And notifications were scanned
    And the worker reports "needs-decision [at=2]: choose"
    And the worker reports "paused [at=3]: waiting"
    When I scan pending notifications twice
    Then the appended decision stays pending with its own sequence

  Scenario: Acknowledgement handles only a presented identity and survives replay
    Given the worker reports "blocked [at=1]: hold"
    And notifications were scanned
    When I acknowledge the presented worker notification twice
    And the worker reports "done [at=2]: later"
    And notifications were scanned
    Then only the later notification remains pending

  Scenario: A replacement cannot be acknowledged using its predecessor's identity
    Given the worker reports "done [at=1]: original"
    And notifications were scanned
    And the ownership record names a replacement generation
    And a new generation status file is published
    And the worker reports "blocked [at=2]: replacement"
    When I acknowledge the first worker generation notification
    Then the replacement remains pending after an old-generation acknowledgement

  Scenario: An unpresented report cannot be acknowledged
    Given the worker reports "blocked [at=1]: hold"
    When I acknowledge the first worker notification
    Then acknowledgement fails and scanning recovers the report

  Scenario: An interrupted handling turn re-presents the same report after restart
    Given the worker reports "needs-decision [at=1]: choose"
    And notifications were scanned
    When I run riddim with:
      """
      notifications scan
      """
    Then the unacknowledged report is replayed without another worker event

  Scenario: Lost historical queue evidence is not a successful empty drain
    Given the worker reports "blocked [at=1]: hold"
    And notifications were scanned
    And the ownership record names a replacement generation
    And a new generation status file is published
    And the first notification file is removed from the old generation
    When I run riddim with:
      """
      notifications scan
      """
    Then the missing queue is reported as a failure

  Scenario: Lost queue evidence is not a successful empty drain
    Given the worker reports "blocked [at=1]: hold"
    And notifications were scanned
    And the first notification file is removed
    When I run riddim with:
      """
      notifications scan
      """
    Then the missing queue is reported as a failure

  Scenario: Routine progress alone does not notify
    Given the worker reports "working [at=1]: started"
    And the worker reports "paused [at=2]: later"
    When I scan pending notifications twice
    Then no notifications were published

  Scenario: Historical pending evidence remains bound to its original generation
    Given the worker reports "failed [at=1]: original"
    And notifications were scanned
    And the ownership record names a replacement generation
    When I scan pending notifications twice
    Then the old notification remains historical and the successor has no claim

  Scenario: A replacement generation reports its own event without adopting an old report
    Given the worker reports "done [at=1]: original"
    And the ownership record names a replacement generation
    And a new generation status file is published
    And the worker reports "failed [at=2]: replacement"
    When I run riddim with:
      """
      notifications scan
      """
    Then only the replacement generation report is pending

  Scenario: A replacement generation cannot adopt an unobserved old report
    Given the worker reports "done [at=1]: original"
    And the ownership record names a replacement generation
    When I run riddim with:
      """
      notifications scan
      """
    Then scanning fails without publishing a notification

  Scenario: Invalid ownership cannot produce a positive claim
    Given the worker reports "done [at=1]: original"
    And the ownership record is invalid for notification scanning
    When I run riddim with:
      """
      notifications scan
      """
    Then scanning fails without publishing a notification

  Scenario: A valid plain task does not block a local-only report
    Given another valid plain task record is present
    And the worker reports "blocked [at=1]: stuck"
    When I run riddim with:
      """
      notifications scan
      """
    Then only the worker report is pending

  Scenario: A legacy local-only record is not a successful empty scan
    Given the worker record has no locked reporting protocol
    When I run riddim with:
      """
      notifications scan
      """
    Then scanning fails without publishing a notification

  Scenario: Symlinked status cannot produce a positive claim
    Given the worker reports "done [at=1]: original"
    And the worker status file is replaced with a symlink
    When I run riddim with:
      """
      notifications scan
      """
    Then scanning fails without publishing a notification

  Scenario: A world-readable status cannot produce a positive claim
    Given the worker reports "done [at=1]: original"
    And the worker status is world-readable
    When I run riddim with:
      """
      notifications scan
      """
    Then scanning fails without publishing a notification

  Scenario: An incomplete event cannot produce a positive claim
    Given the status ends in an incomplete event
    When I run riddim with:
      """
      notifications scan
      """
    Then scanning fails without publishing a notification

  Scenario: Worker reporting succeeds when the notification directory is unavailable
    Given the notification directory is unavailable
    When the current worker reports "done [at=1]: claim" through riddim
    Then reporting succeeds even though observation cannot publish

  Scenario: Replacement during observation cannot attribute an old report to a successor
    Given the worker reports "done [at=1]: original"
    And ownership changes during status classification
    When I run riddim with:
      """
      notifications scan
      """
    Then scanning fails without publishing a notification

  Scenario: A cursor publication failure leaves a durable notification to replay
    Given the worker reports "blocked [at=1]: hold"
    And the notification cursor cannot be replaced
    When I run riddim with:
      """
      notifications scan
      """
    Then the failed scan leaves the same pending identity recoverable
