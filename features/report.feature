Feature: A local-only worker reports through the same lock used for landing

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

  Scenario: Reporting works when the project itself contains no Riddim executable
    Given a local-only task was started
    When I run riddim with:
      """
      result worker
      """
    Then the worker has a usable absolute report command and inherited private state

  Scenario: A new brief binds worker reports to the locked command and this generation
    Given a local-only task was started
    When I run riddim with:
      """
      result worker
      """
    Then the task brief instructs the worker to use its generation-locked report command

  Scenario: Reporting waits for the operator's name lock before appending
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    When the worker tries to report done while the operator holds the name lock
    Then the report waits until the lock is released and result becomes ready

  Scenario: A stale worker cannot report into a replacement generation
    Given a local-only task was started
    When an older generation reports "done [at=123]: old work" through riddim
    Then reporting refuses the stale generation and keeps the status empty

  Scenario: A legacy worker cannot use the new report protocol
    Given a local-only task was started
    And the worker record has no locked reporting protocol
    When the current worker reports "done [at=123]: old work" through riddim
    Then reporting refuses an uncoordinated legacy worker and keeps the status empty

  Scenario: Never append a report through a symlinked status path
    Given a local-only task was started
    And the worker status file is replaced with a symlink
    When the current worker reports "done [at=123]: work committed" through riddim
    Then reporting refuses the symlink and does not change its target

  Scenario: A worker reports its committed work using its own generation
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    When the current worker reports "done [at=123]: work committed" through riddim
    Then the report is accepted and result shows the worker ready
