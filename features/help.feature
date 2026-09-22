Feature: Discover available commands

  Scenario: List the send command
    When I run riddim with:
      """
      """
    Then standard output includes "send <target> <message...>"

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

  Scenario: List the send --wait command
    When I run riddim with:
      """
      """
    Then standard output includes "send --wait <target> <message...>"

  Scenario: Exit successfully when showing help for send --wait
    When I run riddim with:
      """
      """
    Then the command succeeds

  Scenario: Write no error when showing help for send --wait
    When I run riddim with:
      """
      """
    Then standard error is empty

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
    Then standard output includes "peek <target> [lines]"

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
    Then standard output includes "status <target>"

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
    Then standard output includes "interrupt <target>"

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
