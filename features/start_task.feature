Feature: Launch an isolated Pi worker with a durable initial task brief

  Background:
    Given a local Git project for worktree start
    And a config directory with agent profile:
      """
      pi openrouter/z-ai/glm-5.3-flash max
      """
    And Herdr starts the agent only in the linked worktree
    And a fake Pi executable is on PATH for the task launch

  Scenario: Refuse an empty task before allocating a worktree or endpoint
    Given a task file containing:
      """

      """
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then no worker worktree is created

  Scenario: Refuse a symlinked task file before allocating a worktree
    Given a symlinked task file
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then no worker worktree is created

  Scenario: Refuse invalid UTF-8 before allocating a worktree
    Given a task file with invalid UTF-8
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then no worker worktree is created

  Scenario: Refuse an oversized task before allocating a worktree
    Given a task file larger than the brief limit
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then no worker worktree is created

  Scenario: Refuse a task file without an isolated worktree
    When I run riddim with:
      """
      start worker --task-file task.md
      """
    Then the command exits with status 2

  Scenario: Never overwrite a previous brief for the same name
    Given a task file containing:
      """
      Fix the package tests.
      """
    And an existing worker brief
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then no worker worktree is created

  Scenario: Refuse an idle start that would reuse a name with a retained brief
    Given an existing worker brief
    When I run riddim with:
      """
      start worker --worktree
      """
    Then no worker worktree is created

  Scenario: Launch Pi with the full private brief before naming its exact registered pane
    Given a task file containing:
      """
      Fix Riddim's worktree test. Keep the user's instructions intact.
      Run the full test suite.
      """
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then Pi receives a staged full brief launch and is named on its exact pane

  Scenario: A delayed source line cannot launch a replacement task with the same name
    Given a task file containing:
      """
      Original task.
      """
    When I restart the worker with a different task after inspecting and removing its old resources
    Then the original source line cannot launch the replacement task

  Scenario: Keep all ownership evidence when shell submission is unconfirmed
    Given a task file containing:
      """
      Fix the package tests.
      """
    And the shell launch submission is unconfirmed
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then the failed task retains its brief, record, pane, and linked worktree

  Scenario: Keep all ownership evidence if the new pane hosts an unrecognized process
    Given a task file containing:
      """
      Fix the package tests.
      """
    And the new pane does not register Pi
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then the failed task retains its brief, record, pane, and linked worktree

  Scenario: Keep all ownership evidence when the named Pi belongs to a different incarnation
    Given a task file containing:
      """
      Fix the package tests.
      """
    And the new named Pi belongs to another incarnation
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then the failed task retains its brief, record, pane, and linked worktree

  Scenario: Keep all ownership evidence if naming the detected Pi fails
    Given a task file containing:
      """
      Fix the package tests.
      """
    And the new Pi cannot be named
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then the failed task retains its brief, record, pane, and linked worktree
