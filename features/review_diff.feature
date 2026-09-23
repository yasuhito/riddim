Feature: Review a local-only worker branch without changing it

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

  Scenario: Refuse without an ownership record
    When I run riddim with:
      """
      review-diff worker
      """
    Then review-diff refuses without an ownership record

  Scenario: Refuse a regular task
    Given a regular task was started
    When I run riddim with:
      """
      review-diff worker
      """
    Then review-diff refuses a non-local task

  Scenario: Report no committed differences on a fresh branch
    Given a local-only task was started
    When I run riddim with:
      """
      review-diff worker
      """
    Then review-diff reports no changes against local main

  Scenario: Show the stat and patch for a committed worker change
    Given a local-only task was started
    And the worker commits a change in its own branch
    When I run riddim with:
      """
      review-diff worker
      """
    Then review-diff shows the worker's committed patch against local main

  Scenario: Show only the stat when requested
    Given a local-only task was started
    And the worker commits a change in its own branch
    When I run riddim with:
      """
      review-diff worker --stat
      """
    Then review-diff shows only the worker's change statistics

  Scenario: Refuse a replacement owner without leaking a partial diff
    Given a local-only task was started
    And the worker commits a change in its own branch
    And Git replaces the ownership record while preparing the review
    When I run riddim with:
      """
      review-diff worker
      """
    Then review-diff refuses changed ownership without printing a patch

  Scenario: Refuse a symlinked worktree path in the ownership record
    Given a local-only task was started
    And the recorded worker worktree is a symlink
    When I run riddim with:
      """
      review-diff worker
      """
    Then review-diff refuses an untrusted worktree without printing a patch

  Scenario: Refuse an unsupported review option
    When I run riddim with:
      """
      review-diff worker --fetch
      """
    Then review-diff rejects the option before touching a worktree

  Scenario: Refuse a branch that moved away from the worker's checkout
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker checkout is detached
    When I run riddim with:
      """
      review-diff worker
      """
    Then review-diff refuses an unbound branch without printing a patch
