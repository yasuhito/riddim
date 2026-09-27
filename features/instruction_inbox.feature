Feature: Durable local-only worker instructions
  Background:
    Given a published local-only inbox owner "worker"
    And a fake Herdr executable
    And the notification probe sees a running server

  Scenario: Store instructions in order before notifying, and acknowledge one without losing the next
    When I send two instructions to "worker"
    Then "First instruction" and "Second instruction" are ordered and individually acknowledged

  Scenario: Notification sees the saved instruction before it is submitted
    Given Herdr checks that the instruction already exists
    When I run riddim with:
      """
      send worker First instruction
      """
    Then the notification observed the stored instruction

  Scenario: A failed notification is not a failed instruction
    Given the notification fails
    When I run riddim with:
      """
      send worker First instruction
      """
    Then the instruction "First instruction" is stored despite notification failure

  Scenario: The independent watcher can rescan stored instructions without the Pi watcher
    When I run riddim with:
      """
      send worker First instruction
      """
    And I run the instruction watcher after the grace period
    Then the watcher has retried the stored instruction

  Scenario: A restarted watcher does not notify after the worker acknowledges the record
    When I run riddim with:
      """
      send worker First instruction
      """
    And I run the instruction watcher after the grace period
    And I acknowledge the stored instruction and restart the watcher
    Then the restarted watcher does not re-notify the handled instruction

  Scenario: The CLI asks for action after the retry budget and retains the instruction
    When I run riddim with:
      """
      send worker First instruction
      """
    And I run the instruction watcher after the grace period
    And I exhaust the notification budget through the CLI
    Then the instruction remains pending with a durable action request

  Scenario: The CLI does not notify a proven dead worker
    When I run riddim with:
      """
      send worker First instruction
      """
    And I run the instruction watcher after the grace period
    And the worker endpoint is proven dead
    And I run riddim with:
      """
      watch-instructions --once
      """
    Then the instruction remains pending with a durable action request

  Scenario: An invalid retry record fails visibly without discarding the pending instruction
    When I run riddim with:
      """
      send worker First instruction
      """
    And I run the instruction watcher after the grace period
    And the instruction retry record is invalid
    And I run riddim with:
      """
      watch-instructions --once
      """
    Then the watcher reports a retry bookkeeping failure and retains the instruction

  Scenario: A native Pi command still reaches the direct prompt
    When I run riddim with:
      """
      send worker /help
      """
    Then the native command reaches Herdr without an inbox

  Scenario: Refuse a retired owner
    Given the local-only inbox owner is retired
    When I run riddim with:
      """
      send worker First instruction
      """
    Then the retired owner is refused without an inbox

  Scenario: Name reuse never exposes the former generation's instructions
    When I run riddim with:
      """
      send worker First instruction
      """
    And the local-only inbox owner is replaced by a new generation
    And I run riddim with:
      """
      send worker Second instruction
      """
    Then the current inbox contains "Second instruction" and the old inbox contains "First instruction"

  Scenario: Refuse inconsistent local-only ownership before writing
    Given the local-only inbox owner has an inconsistent window
    When I run riddim with:
      """
      send worker First instruction
      """
    Then the unsafe inbox is refused before Herdr

  Scenario: Refuse an unsafe inbox path rather than claiming delivery
    Given the generation inbox is a symlink
    When I run riddim with:
      """
      send worker First instruction
      """
    Then the unsafe inbox is refused before Herdr
