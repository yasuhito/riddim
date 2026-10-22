Feature: Explicit human-approved discard of clean abandoned local-only work

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
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And a fake cwd scan reports no worker process

  Scenario: Inspect exact scope without closing or deleting assets
    When I inspect the worker discard scope
    Then discard inspection names the exact clean scope without mutation

  Scenario: A name alone is not discard authorization
    When I run riddim with:
      """
      discard worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario Outline: All explicit approval fields must match
    Given I inspect the worker discard scope
    And the discard approval field "<field>" is stale
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets

    Examples:
      | field      |
      | generation |
      | head       |
      | snapshot   |

  Scenario: Confirmation flag is mandatory even with matching scope
    Given I inspect the worker discard scope
    When I invoke discard without the confirmation flag
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Discard an explicitly approved unlanded branch after Pi exits
    Given I inspect the worker discard scope
    And Pi already exited the recorded pane
    When I invoke the confirmed discard
    Then authorized discard removes only the worker assets and keeps audit evidence

  Scenario: Discard with the recorded pane already gone
    Given I inspect the worker discard scope
    And the recorded pane is already gone
    When I invoke the confirmed discard
    Then authorized discard removes only the worker assets and keeps audit evidence

  Scenario: A later commit requires fresh approval
    Given I inspect the worker discard scope
    And the worker commits another change after review
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario Outline: New local files are never covered by clean approval
    Given I inspect the worker discard scope
    And the worker gains "<kind>" data
    When I invoke the confirmed discard
    Then discard retains the new local data and worker assets

    Examples:
      | kind      |
      | tracked   |
      | untracked |
      | ignored   |
      | hidden    |

  Scenario: Refuse foreign endpoint identity
    Given I inspect the worker discard scope
    And a different agent occupies the worker pane
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse the caller's own pane
    Given I inspect the worker discard scope
    And the caller is the recorded worker pane
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Recheck complete ownership after backend probes
    Given I inspect the worker discard scope
    And the ownership record changes during the agent probe in field "herdr_tab_id"
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Recheck source after pane close before removing files
    Given I inspect the worker discard scope
    And the cwd scan creates untracked worker data
    When I invoke the confirmed discard
    Then discard retains the new local data and worker assets

  Scenario: Keep remaining assets and attempt evidence on Git removal failure
    Given I inspect the worker discard scope
    And Git refuses to remove the worker worktree
    When I invoke the confirmed discard
    Then incomplete discard keeps the record, Git assets and attempt evidence

  Scenario: Keep branch and record when compare-and-delete fails after worktree removal
    Given I inspect the worker discard scope
    And Git refuses discard branch deletion
    When I invoke the confirmed discard
    Then incomplete discard keeps the branch and record after worktree removal

  Scenario: Refuse uncertain endpoint disappearance
    Given I inspect the worker discard scope
    And the pane read after close is ambiguous
    When I invoke the confirmed discard
    Then incomplete discard keeps the record, Git assets and attempt evidence

  Scenario: Branch movement during deletion cannot delete an unapproved tip
    Given I inspect the worker discard scope
    And Git moves the worker branch during discard deletion
    When I invoke the confirmed discard
    Then incomplete discard retains the changed branch and record

  Scenario: A live process in the worker checkout prevents Git removal
    Given I inspect the worker discard scope
    And a fake cwd scan reports a worker process
    When I invoke the confirmed discard
    Then incomplete discard keeps the record, Git assets and attempt evidence

  Scenario: Inspection refuses dirty work instead of minting blanket approval
    Given the worker gains "untracked" data
    When I run riddim with:
      """
      discard worker --inspect
      """
    Then discard retains the new local data and worker assets

  Scenario: Marked workers cannot authorize discard
    Given I inspect the worker discard scope
    And the discard caller is a marked worker
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets
