Feature: Launch an isolated Pi worker with a durable initial task brief

  Background:
    Given a local Git project for worktree start
    And a config directory with agent profile:
      """
      pi openrouter/z-ai/glm-5.3-flash max
      """
    And Herdr starts the agent only in the linked worktree

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

  Scenario: Publish a private worker-role brief and pass its pointer into Pi's initial arguments
    Given a task file containing:
      """
      Fix Riddim's worktree test. Keep the user's instructions intact.
      Run the full test suite.
      """
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then Pi receives a pointer to the published worker brief as its initial prompt

  Scenario: Keep the brief after an unconfirmed agent-start failure
    Given a task file containing:
      """
      Fix the package tests.
      """
    And the new agent start fails in the linked worktree
    When I run riddim with:
      """
      start worker --worktree --task-file task.md
      """
    Then the failed task retains its brief and linked worktree
