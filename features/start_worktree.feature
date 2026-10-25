Feature: Start a Pi worker in an isolated Git worktree

  Background:
    Given a local Git project for worktree start
    And a config directory with agent profile:
      """
      pi openrouter/z-ai/glm-5.3-flash max
      """
    And Herdr starts the agent only in the linked worktree

  Scenario: Create a linked worktree from the local HEAD and start in it
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the worker has a separate linked worktree at the project's HEAD

  Scenario: Keep target parents clean with central runtime storage
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the worker lives in the central runtime without changing the target parent

  Scenario: Resolve a linked runtime back to its primary installation
    Given Riddim runs from a linked runtime checkout
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the primary runtime remains clean with central workers outside it

  Scenario Outline: Use the actual primary installation with relocated Git metadata
    Given Riddim runs from a "<layout>" primary installation
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the worker lives in the central runtime without changing the target parent

    Examples:
      | layout           |
      | separate-git-dir |
      | submodule        |

  Scenario Outline: Refuse an ambiguous linked runtime before allocating a worker
    Given Riddim runs from a "<layout>" primary installation
    And Riddim is invoked from its linked runtime
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the ambiguous runtime is refused without worker assets in Git metadata

    Examples:
      | layout           |
      | separate-git-dir |
      | submodule        |

  Scenario: Linked target checkouts share the repository's central identity
    Given the target is accessed through a linked checkout
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the worker lives in the central runtime without changing the target parent

  Scenario Outline: Refuse unsafe central storage without touching other paths
    Given the central storage has an unsafe "<kind>"
    When I run riddim with:
      """
      start worker --worktree
      """
    Then unsafe central storage is refused without changing its contents

    Examples:
      | kind                |
      | root symlink        |
      | repository symlink  |
      | root file           |
      | repository file     |
      | writable root       |
      | destination symlink |

  Scenario: Remove only newly created empty storage after a branch collision
    Given the worker branch already exists without a worktree
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the failed allocation leaves no central directories or changed branch

  Scenario: Keep same-name independent repositories in separate central directories
    Given another independent project with the same basename has a worker
    When I run riddim with:
      """
      start worker --worktree
      """
    Then both repositories have separate central workers

  Scenario: Refuse a checkout hook that changes the new branch's HEAD
    Given the project has an earlier commit and a post-checkout hook resets the worker branch
    When I run riddim with:
      """
      start worker --worktree
      """
    Then no Herdr workspace is created for the changed worker branch

  Scenario: The worker's copied Riddim CLI shares the original profile and state without environment setup
    Given the project contains the Riddim CLI
    When I run riddim with:
      """
      start worker --worktree
      """
    Then Riddim inside the worktree can start another agent using the original profile and state

  Scenario: A symlinked Git-admin runtime marker refuses rather than routing to a new state directory
    Given the project contains the Riddim CLI
    When I run riddim with:
      """
      start worker --worktree
      """
    And I replace the worker's runtime marker with a symlink
    Then Riddim in the worktree refuses the marker

  Scenario: An explicit state directory overrides the inherited state directory
    Given the project contains the Riddim CLI
    When I run riddim with:
      """
      start worker --worktree
      """
    Then Riddim in the worktree respects an explicit state override

  Scenario: Report where the worker's new branch lives
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the start output names the new worktree and branch

  Scenario: Start Herdr in the new worktree without focusing it
    When I run riddim with:
      """
      start worker --worktree
      """
    Then Herdr creates a workspace in the new worktree without focus

  Scenario: Record the project, branch and worktree alongside the exact endpoint
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the worker record binds the new worktree and its exact Herdr pane

  Scenario: Refuse a second start without allocating another worktree
    Given an existing endpoint record for "worker" that is not a record
    When I run riddim with:
      """
      start worker --worktree
      """
    Then no worker worktree is created

  Scenario: Do not overwrite an existing destination
    Given the worker worktree destination already exists
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the existing worker destination is untouched

  Scenario: Refuse a directory that is not a Git project
    Given the start directory is outside the Git project
    When I run riddim with:
      """
      start worker --worktree
      """
    Then Herdr never creates a workspace

  Scenario: Preserve the worktree when Herdr cannot create a workspace
    Given Herdr refuses to create a workspace with status 7 and error "cannot create workspace"
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the failed start leaves the linked worktree intact

  Scenario: Refuse a client before creating a worktree
    Given the Herdr client reports version "0.7.5"
    When I run riddim with:
      """
      start worker --worktree
      """
    Then no worker worktree is created

  Scenario: Keep a failed Herdr preflight from allocating a worktree
    Given the Herdr client reports version "0.9.0"
    And the Herdr client status read fails
    When I run riddim with:
      """
      start worker --worktree
      """
    Then no worker worktree is created

  Scenario: Forward a failed Herdr preflight without a Ruby backtrace
    Given the Herdr client reports version "0.9.0"
    And the Herdr client status read fails
    When I run riddim with:
      """
      start worker --worktree
      """
    Then standard error is "status failed"

  Scenario: Keep the worktree when Pi fails to start
    Given the new agent start fails in the linked worktree
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the failed start leaves the linked worktree intact

  Scenario: Never launch Pi in a pane whose cwd is not the linked worktree
    Given the new pane stays outside the linked worktree
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the misplaced pane is closed without deleting the worktree

  Scenario: Trust an extension-bearing worktree before creating its workspace
    Given the project contains a Pi extension
    And the Pi trust store contains a denial for the worktree parent
    And Herdr checks Pi trust before creating a workspace
    When I run riddim with:
      """
      start worker --worktree
      """
    Then only the exact worktree has a new trust decision

  Scenario: Create a private Pi trust store when the extension-bearing worktree needs one
    Given the project contains a Pi extension
    And the Pi trust store directory does not exist
    And Herdr checks Pi trust before creating a workspace
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the new Pi trust store contains only the worktree trust

  Scenario: Leave Pi trust unchanged for a worktree without resources
    Given the Pi trust store contains a denial for the worktree parent
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the Pi trust store remains unchanged

  Scenario: Do not create a Pi trust store for a worktree without resources
    Given the Pi trust store directory does not exist
    When I run riddim with:
      """
      start worker --worktree
      """
    Then the Pi trust store directory remains absent
