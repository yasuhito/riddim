Feature: Retire only landed local-only worker assets

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

  Scenario: Refuse a non-local task before touching its pane
    Given a regular task was started
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse to close the pane running this very command
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the caller is the recorded worker pane
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse self-teardown when Herdr uses its implicit default session
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the caller is the recorded worker pane with the default session implicit
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse a force flag without touching Herdr
    When I run riddim with:
      """
      teardown worker --force
      """
    Then teardown refuses an unsupported force flag without touching Herdr

  Scenario: Retire a landed clean worker while keeping generation-local evidence
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown confirms the pane gone, retires the linked worktree and branch, and archives the brief

  Scenario: Target the record's session rather than the ambient session
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the Herdr session is "another-session"
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown confirms the pane gone, retires the linked worktree and branch, and archives the brief

  Scenario: Archiving the brief frees the same worker name for a new generation
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    When I run riddim with:
      """
      teardown worker
      """
    And a fresh fake pane and task input are prepared
    And I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only
      """
    Then the archived brief survives beside a new worker generation

  Scenario: Do not confuse the same pane ID in another session with the recorded pane
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the caller has the same pane ID in another session
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown confirms the pane gone, retires the linked worktree and branch, and archives the brief

  Scenario: Run from outside the project when the cwd scan sees no project process
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the caller and cwd scan are outside the project
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown confirms the pane gone, retires the linked worktree and branch, and archives the brief

  Scenario: A confirmed already-gone pane needs no second close
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the recorded pane is already gone
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown retires the linked worktree without closing the pane again

  Scenario: Retire a landed worker whose Pi already exited from its exact pane
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And Pi already exited the recorded pane
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown confirms the pane gone, retires the linked worktree and branch, and archives the brief

  Scenario: Refuse to discard an unmerged worker commit
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And a fake cwd scan reports no worker process
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse a dirty project checkout even if the worker is clean
    Given a local-only task was started
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse a dirty worker even if its branch was merged
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And the worker leaves an untracked file
    And a fake cwd scan reports no worker process
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Keep the name locked while scanning processes and removing assets
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And a competing writer attempts to replace the owner during the cwd scan
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown blocks the competing owner until the original assets are retired

  Scenario: Retain assets when exact pane disappearance is unconfirmed
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the pane read after close is ambiguous
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses and keeps the linked worktree, branch, and ownership record

  Scenario: Refuse a worker without an ungated done report
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse an existing generation archive before touching the pane
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the generation archive already exists
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse a different pane occupant even if the task is landed
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And a different agent occupies the worker pane
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Refuse a symlinked worker worktree without touching its pane
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the recorded worker worktree is a symlink
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses before closing the pane and keeps all worker assets

  Scenario: Retain assets when the cwd scan returns malformed records
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the cwd scan returns a malformed record
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses and keeps the linked worktree, branch, and ownership record

  Scenario: Retain assets when the cwd scan fails
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the cwd scan cannot finish
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses and keeps the linked worktree, branch, and ownership record

  Scenario: A refused Git worktree removal keeps all unremoved assets
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And Git refuses to remove the worker worktree
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses and keeps the linked worktree, branch, and ownership record

  Scenario: A new decision report after pane closure blocks Git cleanup
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports no worker process
    And the cwd scan observes a new decision report
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses and keeps the linked worktree, branch, and ownership record

  Scenario: Retain assets when a process still has the worktree as cwd
    Given a local-only task was started
    And the task input is removed after launch
    And the worker commits a change in its own branch
    And the worker reports "done [at=123]: work committed"
    And the worker branch is fast-forward merged into local main
    And a fake cwd scan reports a worker process
    When I run riddim with:
      """
      teardown worker
      """
    Then teardown refuses and keeps the linked worktree, branch, and ownership record
