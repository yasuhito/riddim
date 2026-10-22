Feature: Explicit human-approved discard of abandoned local-only work

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

  Scenario: Refuse foreign endpoint identity even for reviewed dirty files
    Given the worker has reviewable dirty files
    And I inspect the worker discard scope
    And a different agent occupies the worker pane
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse the caller's own pane even for reviewed dirty files
    Given the worker has reviewable dirty files
    And I inspect the worker discard scope
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

  Scenario: Dirty inspection presents a reviewable exact inventory
    Given the worker has reviewable dirty files
    When I inspect the worker discard scope
    Then discard inspection inventories the exact dirty files without mutation

  Scenario: Explicit approval covers reviewed staged, unstaged, deleted and untracked files
    Given the worker has reviewable dirty files
    And I inspect the worker discard scope
    When I invoke the confirmed discard
    Then authorized discard removes only the worker assets and keeps audit evidence

  Scenario Outline: Every dirty snapshot change needs fresh approval
    Given the worker has reviewable dirty files
    And I inspect the worker discard scope
    And the reviewed dirty files change in "<kind>"
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets

    Examples:
      | kind              |
      | tracked content   |
      | new file          |
      | deleted file      |
      | staged content    |
      | staged state      |
      | untracked content |
      | executable mode   |
      | same stat content |

  Scenario Outline: Unsupported content never receives an approval snapshot
    Given the worker has unsupported "<kind>" content
    When I run riddim with:
      """
      discard worker --inspect
      """
    Then teardown refuses before closing the pane and keeps all worker assets

    Examples:
      | kind             |
      | ignored          |
      | sensitive        |
      | nested repo      |
      | bare repo        |
      | symlink          |
      | hardlink         |
      | control filename |
      | hidden           |
      | skip-worktree    |
      | submodule        |
      | intent-to-add    |
      | conflicted       |
      | index lock       |

  Scenario: Dirty removal failure leaves explicit loss evidence
    Given the worker has reviewable dirty files
    And I inspect the worker discard scope
    And Git refuses to remove the worker worktree
    When I invoke the confirmed discard
    Then incomplete dirty discard records file loss before removal failure

  Scenario: Clean tracked sensitive-looking fixtures remain discardable
    Given the worker committed sensitive-looking fixtures
    And I inspect the worker discard scope
    When I invoke the confirmed discard
    Then authorized discard removes only the worker assets and keeps audit evidence

  Scenario Outline: Dirty or untracked sensitive-looking files still refuse inspection
    Given the worker committed sensitive-looking fixtures
    And a sensitive-looking fixture changes in "<kind>"
    When I run riddim with:
      """
      discard worker --inspect
      """
    Then teardown refuses before closing the pane and keeps all worker assets

    Examples:
      | kind           |
      | unstaged       |
      | staged         |
      | preserved stat |
      | deleted        |
      | untracked      |

  Scenario: Duplicate status paths cannot hide staged deletion
    Given the worker untracks a file without removing its contents
    When I run riddim with:
      """
      discard worker --inspect
      """
    Then discard explicitly refuses duplicate status paths without mutation

  Scenario: Marked workers cannot authorize discard
    Given I inspect the worker discard scope
    And the discard caller is a marked worker
    When I invoke the confirmed discard
    Then teardown refuses before closing the pane and keeps all worker assets
