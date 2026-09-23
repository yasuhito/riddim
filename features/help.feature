Feature: Discover available commands

  Scenario: List the process-evidence command
    When I run riddim with:
      """
      """
    Then standard output includes "process-state <name>"

  Scenario: List the server-state command
    When I run riddim with:
      """
      """
    Then standard output includes "server-state <name>"

  Scenario: List the composer-state command
    When I run riddim with:
      """
      """
    Then standard output includes "composer-state <name>"

  Scenario: List the exit command
    When I run riddim with:
      """
      """
    Then standard output includes "exit <name>"

  Scenario: List the foreground working-directory command
    When I run riddim with:
      """
      """
    Then standard output includes "current-path <name>"

  Scenario: List the exact-pane presence command
    When I run riddim with:
      """
      """
    Then standard output includes "pane-presence <name>"

  Scenario: List the native-activity command
    When I run riddim with:
      """
      """
    Then standard output includes "busy-state <name>"

  Scenario: List the process-state command
    When I run riddim with:
      """
      """
    Then standard output includes "agent-state <name>"

  Scenario: List the ownership inventory command
    When I run riddim with:
      """
      """
    Then standard output includes "list [--json]"

  Scenario: List the send command
    When I run riddim with:
      """
      """
    Then standard output includes "send <name> <message...>"

  Scenario: Exit successfully when showing help for send
    When I run riddim with:
      """
      """
    Then the command succeeds

  Scenario: Write no error when showing help for send
    When I run riddim with:
      """
      """
    Then standard error is empty

  Scenario: List the read-only review command
    When I run riddim with:
      """
      """
    Then standard output includes "review-diff <name> [--stat]"

  Scenario: List the start command
    When I run riddim with:
      """
      """
    Then standard output includes "start <name>"

  Scenario: Exit successfully when showing help for start
    When I run riddim with:
      """
      """
    Then the command succeeds

  Scenario: Write no error when showing help for start
    When I run riddim with:
      """
      """
    Then standard error is empty

  Scenario: List the peek command
    When I run riddim with:
      """
      """
    Then standard output includes "peek <name> [lines|--visible]"

  Scenario: Exit successfully when showing help for peek
    When I run riddim with:
      """
      """
    Then the command succeeds

  Scenario: Write no error when showing help for peek
    When I run riddim with:
      """
      """
    Then standard error is empty

  Scenario: List the status command
    When I run riddim with:
      """
      """
    Then standard output includes "status <name>"

  Scenario: Exit successfully when showing help for status
    When I run riddim with:
      """
      """
    Then the command succeeds

  Scenario: Write no error when showing help for status
    When I run riddim with:
      """
      """
    Then standard error is empty

  Scenario: List the interrupt command
    When I run riddim with:
      """
      """
    Then standard output includes "interrupt <name>"

  Scenario: Exit successfully when showing help for interrupt
    When I run riddim with:
      """
      """
    Then the command succeeds

  Scenario: Write no error when showing help for interrupt
    When I run riddim with:
      """
      """
    Then standard error is empty
