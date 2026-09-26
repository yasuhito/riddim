Feature: A local-only task reports a claim, not inferred completion

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
      Add a focused regression test and report the result.
      """

  Scenario: Refuse local-only without an initial brief before creating assets
    When I run riddim with:
      """
      start worker --worktree --mode local-only
      """
    Then no worker worktree is created

  Scenario: Refuse a conflicting delivery contract before allocating an endpoint
    Given a task file containing:
      """
      Fix the tests.
      Delivery contract: mode=direct-PR
      """
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only
      """
    Then the conflicting delivery contract is refused before publication

  Scenario: Refuse even a second conflicting delivery contract line
    Given a task file containing:
      """
      Delivery contract: mode=local-only
      Delivery contract: mode=direct-PR
      Fix the tests.
      """
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only
      """
    Then the conflicting delivery contract is refused before publication

  Scenario: A matching explicit delivery contract is accepted
    Given a task file containing:
      """
      Delivery contract: mode=local-only
      Fix the tests without pushing.
      """
    Given a local-only task was started
    Then the local-only brief puts the binding delivery contract before the task

  Scenario: A task's request to push cannot override local-only delivery
    Given a task file containing:
      """
      Change a test, commit, and push your branch.
      """
    Given a local-only task was started
    Then the local-only brief puts the binding delivery contract before the task

  Scenario: A regular task is not silently treated as local-only
    Given a regular task was started
    When I run riddim with:
      """
      result worker
      """
    Then the result command refuses a regular task

  Scenario: A new local-only worker has no outcome yet
    Given a local-only task was started
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "unreported"

  Scenario: An idle worker's uncommitted done claim is not ready
    Given a local-only task was started
    And the worker reports "done [at=17]: ready for review"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "reported (not ready): done [at=17]: ready for review"

  Scenario: A committed, clean and fast-forwardable local-only branch is ready
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "done [at=17]: tests passed"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "ready: done [at=17]: tests passed"

  Scenario: Untracked work prevents a ready claim
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker leaves an untracked file
    And the worker reports "done [at=17]: tests passed"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "reported (not ready): done [at=17]: tests passed"

  Scenario: A changed main branch prevents a fast-forward handoff
    Given a local-only task was started
    And the worker commits a change in its own branch
    And main advances independently
    And the worker reports "done [at=17]: tests passed"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "reported (not ready): done [at=17]: tests passed"

  Scenario: A later blocker supersedes an earlier done event
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "done [at=17]: tests passed"
    And the worker reports "blocked [at=18]: waiting for a decision"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "reported: blocked [at=18]: waiting for a decision"

  Scenario: A done event cannot silently close an earlier decision
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "needs-decision [at=16]: can this change ship?"
    And the worker reports "done [at=17]: tests passed"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "reported (not ready): done [at=17]: tests passed"

  Scenario: A keyed answer closes only its own decision after durable delivery
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "needs-decision [at=16] [key=alpha]: choose A"
    And the worker reports "blocked [at=17] [key=beta]: wait for B"
    When I run riddim with:
      """
      send worker --resolve-key alpha Choose A
      """
    When the worker reports "done [at=18]: tests passed"
    And I run riddim with:
      """
      result worker
      """
    Then the local-only result is "reported (not ready): done [at=18]: tests passed"

  Scenario: A resolved decision permits a subsequent done and exact-tip review
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "needs-decision [at=16]: choose A"
    When I run riddim with:
      """
      send worker --resolve-key default Choose A
      """
    When the worker reports "done [at=18]: tests passed"
    And I run riddim with:
      """
      result worker
      """
    Then the local-only result is "ready: done [at=18]: tests passed"

  Scenario: A durable answer whose close cannot fit stays visible and must not be resent
    Given a local-only task was started
    And the worker status is nearly full with an open decision
    When I run riddim with:
      """
      send worker --resolve-key default Choose A
      """
    Then the answer is stored but its decision remains open for repair

  Scenario: A key mentioned in question prose cannot impersonate its decision key
    Given a local-only task was started
    And the worker reports "needs-decision [at=16]: Should docs mention [key=alpha]?"
    When I run riddim with:
      """
      send worker --resolve-key alpha Choose A
      """
    Then the wrong key is refused without storing an answer

  Scenario: A slash-prefixed keyed answer is stored as text, not run as a command
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "needs-decision [at=16]: Which path?"
    And the supervisor answers key "default" with "/usr/local/bin"
    And the worker reports "done [at=17]: tests passed"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "ready: done [at=17]: tests passed"

  Scenario: A failure remains a gate after an unrelated keyed answer
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "failed [at=15]: tests failed"
    And the worker reports "needs-decision [at=16]: Which path?"
    And the supervisor answers key "default" with "/usr/local/bin"
    And the worker reports "done [at=17]: tests passed"
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result is "reported (not ready): done [at=17]: tests passed"

  Scenario: An already answered key cannot deliver a duplicate answer
    Given a local-only task was started
    And the worker reports "needs-decision [at=16] [key=alpha]: choose A"
    And the supervisor answers key "alpha" with "Choose A"
    When I run riddim with:
      """
      send worker --resolve-key alpha Choose A again
      """
    Then the wrong key is refused without storing another answer

  Scenario: A report concurrent with a keyed answer cannot erase an unrelated blocker
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "needs-decision [at=16] [key=alpha]: choose A"
    When the worker reports a blocker while the supervisor answers key "alpha"
    Then the unrelated blocker remains open

  Scenario: A wrong key refuses before delivery
    Given a local-only task was started
    And the worker reports "needs-decision [at=16] [key=alpha]: choose A"
    When I run riddim with:
      """
      send worker --resolve-key beta Choose B
      """
    Then the wrong key is refused without storing an answer

  Scenario: An old generation's report is not attributed to a replacement record
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "done [at=17]: tests passed"
    And the ownership record names a replacement generation
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result begins with "unknown ("

  Scenario: Malformed status events are not accepted as done
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker status contains a malformed event
    When I run riddim with:
      """
      result worker
      """
    Then the result command refuses malformed status evidence

  Scenario: Refuse a symlinked worker status file
    Given a local-only task was started
    And the worker status file is replaced with a symlink
    When I run riddim with:
      """
      result worker
      """
    Then the local-only result begins with "unknown ("
