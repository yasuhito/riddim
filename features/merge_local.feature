Feature: Land an approved local-only worker branch into local main

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

  Scenario: Land the approved reviewed tip as a strict fast-forward
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    When I run riddim merge-local with the approved head
    Then merge-local moves local main to the approved tip and reports the exact tips

  Scenario: Refuse a reviewed head the branch has moved past
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the worker commits another change in its own branch
    When I run riddim merge-local with the approved head
    Then merge-local refuses a stale reviewed head without moving local main

  Scenario: Refuse an ownership record replaced during the merge checks
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And Git replaces the ownership record during the merge checks
    When I run riddim merge-local with the approved head
    Then merge-local refuses changed ownership without moving local main

  Scenario: Refuse an ownership record replaced during the fast-forward
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And Git replaces the ownership record during the fast-forward
    When I run riddim merge-local with the approved head
    Then merge-local reports the landed main without claiming a verified merge

  Scenario: Keep the name locked through Git's fast-forward
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And a competing writer attempts to claim the name during the fast-forward
    When I run riddim merge-local with the approved head
    Then merge-local keeps the name locked through the fast-forward and lands the approved tip

  Scenario: Refuse the marked task worker actor
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the caller is the marked task worker
    When I run riddim merge-local with the approved head
    Then merge-local refuses the branch actor without moving local main

  Scenario: Refuse an unknown actor marker as a wiring bug
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the caller has an unknown actor marker
    When I run riddim merge-local with the approved head
    Then merge-local refuses the unknown actor without moving local main

  Scenario: Refuse invocation from the worker checkout instead of the project
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the command runs from the worker worktree
    When I run riddim merge-local with the approved head
    Then merge-local refuses the wrong checkout without moving local main

  Scenario: Refuse a project checkout off local main
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the project checkout is on another branch
    When I run riddim merge-local with the approved head
    Then merge-local refuses a project checkout off local main without moving it

  Scenario: Refuse a dirty project checkout
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the project checkout is dirty
    When I run riddim merge-local with the approved head
    Then merge-local refuses the dirty project without moving local main

  Scenario: Refuse a dirty worker worktree
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the worker leaves an untracked file
    When I run riddim merge-local with the approved head
    Then merge-local refuses the dirty worker without moving local main

  Scenario: Refuse a main that has diverged from the worker branch
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And main advances independently
    When I run riddim merge-local with the approved head
    Then merge-local refuses the diverged branch without moving local main

  Scenario: Refuse work that local main already contains
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And the worker branch is fast-forward merged into local main
    When I run riddim merge-local with the approved head
    Then merge-local refuses the already-landed branch without moving local main

  Scenario: Refuse a worker with no status report
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the operator approves the reviewed worker branch tip
    When I run riddim merge-local with the approved head
    Then merge-local refuses without an ungated done report

  Scenario: Refuse a done report that follows an open decision
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "needs-decision [at=122]: unclear base"
    And the worker reports "done [at=124]: work committed"
    And the operator approves the reviewed worker branch tip
    When I run riddim merge-local with the approved head
    Then merge-local refuses the open decision gate

  Scenario: Land without remote, cleanup, or Herdr side effects
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the operator approves the reviewed worker branch tip
    And Git records every invocation during the merge
    When I run riddim merge-local with the approved head
    Then merge-local lands the tip while Herdr, remotes, and worker assets stay untouched

  Scenario: Refuse a head argument that is not a full commit id
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    When I run riddim with:
      """
      merge-local worker --head abc123
      """
    Then merge-local rejects a short head before reading any state

  Scenario: Refuse without an ownership record
    When I run riddim with:
      """
      merge-local worker --head 0123456789abcdef0123456789abcdef01234567
      """
    Then merge-local refuses without an ownership record

  Scenario: Refuse a non-local task
    Given a regular task was started
    And the operator approves the reviewed worker branch tip
    When I run riddim merge-local with the approved head
    Then merge-local refuses a non-local task
