Feature: A read-only fleet overview of recorded workers

  A smaller subset of Firstmate's fleet snapshot for one selected Riddim state
  directory: validated ownership records in stable name order, each row pairing
  its captured identity with separately attributed evidence - this generation's
  read-only local-only report claim and the exact recorded pane's Pi process
  view. It is not Firstmate's fleet state: no backlog, registered secondmates,
  remote summaries, PRs, notifications, or inferred current crew state. A
  report outcome is a claim, not approval; idle is not done and report history
  is not current crew state.

  Rule: Pair each recorded worker's claim with its process evidence

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
      Commit one change and report completion.
      """
      And a local-only task was started
      And the worker commits a change in its own branch
      And the worker reports "done [at=17]: tests passed"

    Scenario: Pair the git-verified report with the Pi process evidence
      When I run riddim with:
      """
      fleet --json
      """
      Then the snapshot pairs the git-verified report with the Pi process evidence

    Scenario: Render the same facts for humans
      When I run riddim with:
      """
      fleet
      """
      Then the human view renders the JSON record's facts

    Scenario: Git readiness inspection does not refresh the worker's Git index
      Given the worker's tracked file has stale index metadata
      When I run riddim with:
      """
      fleet --json
      """
      Then the worker Git index bytes and mtime are unchanged

  Rule: A record without a task mode has no report surface

    Background:
      Given a fake Herdr executable
      And a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Do not fabricate a local-only report for a plain record
      When I run riddim with:
      """
      fleet --json
      """
      Then the row observes the pane without a report surface

    Scenario: An unreadable process view stays unreadable
      Given the Pi process view is unreadable
      When I run riddim with:
      """
      fleet --json
      """
      Then the unreadable process observation is not a positive claim

    Scenario: Read only the exact recorded pane's process view
      When I run riddim with:
      """
      fleet --json
      """
      Then Herdr reads only the exact recorded process view

  Rule: Enumerate the selected state directory in stable name order

    Background:
      Given a fake Herdr executable
      And a published endpoint record for "zeta" in session "secondary" naming pane "w8:p1"
      And a published endpoint record for "alpha" in session "riddim" naming pane "w9:p1"

    Scenario: Order rows by record name
      When I run riddim with:
      """
      fleet --json
      """
      Then the rows are in record name order

  Rule: An absent or empty state directory is an empty fleet

    Scenario: An absent state directory has an empty JSON fleet
      When I run riddim with:
      """
      fleet --json
      """
      Then standard output is the empty fleet snapshot

    Scenario: The empty human view still names its state directory
      Given an empty state directory
      When I run riddim with:
      """
      fleet
      """
      Then the human view reports no records

    Scenario: The snapshot names the selected state directory
      Given an empty state directory
      When I run riddim with:
      """
      fleet --json
      """
      Then the snapshot names the selected state directory

  Rule: Report claims keep their history gates

    Background:
      Given a fake Herdr executable
      And a published local-only record for "worker" with status events:
      """
      needs-decision [at=16]: can this change ship?
      done [at=17]: tests passed
      """

    Scenario: A later done cannot clear an earlier decision
      When I run riddim with:
      """
      fleet --json
      """
      Then the ready-looking done stays gated by the earlier decision

    Scenario: A pipe in a report does not add a Markdown column
      Given the worker reports a pipe-containing event
      When I run riddim with:
      """
      fleet
      """
      Then the human view keeps the pipe inside its report cell

  Rule: Mutable evidence belongs only to the captured generation

    Background:
      Given a fake Herdr executable
      And a published local-only record for "worker" with status events:
      """
      done [at=17]: tests passed
      """

    Scenario: Discard mutable evidence when ownership changes during observation
      Given ownership is rebound while Herdr reads the process view
      When I run riddim with:
      """
      fleet --json
      """
      Then the row keeps the captured identity without mutable evidence

    Scenario: A same-generation pane change between record reads cannot change the observed pane
      Given the recorded pane changes after endpoint capture
      When I run riddim with:
      """
      fleet --json
      """
      Then the row retains its first pane without another pane's evidence

    Scenario: A record removed after enumeration is absent, not a null row
      Given the record disappears after enumeration
      When I run riddim with:
      """
      fleet
      """
      Then the human view reports no records

    Scenario: A record removed while observing keeps identity without stale evidence
      Given the record disappears while Herdr reads the process view
      When I run riddim with:
      """
      fleet --json
      """
      Then the row keeps the captured identity without mutable evidence

  Rule: Fail closed instead of rendering partial ownership

    Background:
      Given a fake Herdr executable
      And a published endpoint record for "alpha" in session "riddim" naming pane "w9:p1"
      And an existing endpoint record for "zeta" that is not a record

    Scenario: Do not render a partial human view
      When I run riddim with:
      """
      fleet
      """
      Then standard output is empty

    Scenario: Explain the invalid record
      When I run riddim with:
      """
      fleet
      """
      Then standard error includes "the endpoint record for zeta"

    Scenario: Do not emit partial JSON for a malformed record
      When I run riddim with:
      """
      fleet --json
      """
      Then standard output is empty

  Rule: Fleet has no positional selector

    Scenario: Reject unexpected arguments
      When I run riddim with:
      """
      fleet worker
      """
      Then the command exits with status 2
