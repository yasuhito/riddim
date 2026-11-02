Feature: Start only models the local allowlist names exactly

  Background:
    Given a local Git project for worktree start
    And the project checkout is on main
    And a config directory with agent profile:
      """
      pi openai-codex/gpt-6.1-sol high
      """
    And the config directory allows models:
      """
      openai-codex/gpt-6.1-sol
      claude-bridge/claude-opus-5-5
      """
    And Herdr starts the agent only in the linked worktree
    And a fake Pi executable is on PATH for the task launch
    And a task file containing:
      """
      Delivery contract: mode=local-only
      Complete the local task.
      """

  Scenario Outline: Launch a listed default or override
    Given Pi records its exact launch arguments and profile
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only <flags>
      """
    Then Pi and the ownership record select model "<model>" and effort "<effort>" without changing config

    Examples:
      | flags                                                | model                         | effort |
      |                                                      | openai-codex/gpt-6.1-sol      | high   |
      | --effort low                                         | openai-codex/gpt-6.1-sol      | low    |
      | --model claude-bridge/claude-opus-5-5                | claude-bridge/claude-opus-5-5 | high   |
      | --model=claude-bridge/claude-opus-5-5 --effort xhigh | claude-bridge/claude-opus-5-5 | xhigh  |

  Scenario: Pin the provider of a slashed model ID for the task launch
    Given the config directory allows models:
      """
      openrouter/openai/gpt-5.5
      """
    And Pi records its exact launch arguments and profile
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only --model openrouter/openai/gpt-5.5
      """
    Then Pi and the ownership record select model "openrouter/openai/gpt-5.5" and effort "high" without changing config

  Scenario: Pin the provider for a native start
    Given Herdr creates workspace "w9" and starts the agent
    When I run riddim with:
      """
      start worker --model claude-bridge/claude-opus-5-5
      """
    Then Herdr starts agent "worker" in pane "w9:p1" with model "claude-bridge/claude-opus-5-5" and effort "high"

  Scenario: Read a commented allowlist with duplicates and surrounding whitespace
    Given the config directory allows models:
      """
      # Human-approved models for Riddim launches

        claude-bridge/claude-opus-5-5
      claude-bridge/claude-opus-5-5
      """
    And Pi records its exact launch arguments and profile
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only --model claude-bridge/claude-opus-5-5
      """
    Then Pi and the ownership record select model "claude-bridge/claude-opus-5-5" and effort "high" without changing config

  Scenario Outline: Refuse an unlisted override before provisioning
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only --model <model> <effort>
      """
    Then start refuses before creating any worker assets or invoking Herdr

    Examples:
      | model                                      | effort         |
      | openrouter/anthropic/claude-opus-5.5       |                |
      | openrouter/anthropic/claude-opus-5.5       | --effort low   |
      | openrouter/claude-bridge/claude-opus-5-5   |                |
      | openrouter/anthropic/claude-opus-5-5       |                |
      | claude-opus-5-5                            |                |
      | claude-bridge/claude-opus-5.5              |                |
      | Claude-Bridge/claude-opus-5-5              |                |
      | claude-bridge/claude-opus-5-5-thinking     |                |
      | claude-bridge/*                            |                |
      | "provider/a'b = c"                         |                |

  Scenario Outline: Refuse an unlisted profile default whatever the effort
    Given the config directory allows models:
      """
      claude-bridge/claude-opus-5-5
      """
    When I run riddim with:
      """
      start worker <flags>
      """
    Then start refuses before creating any worker assets or invoking Herdr

    Examples:
      | flags                                                    |
      |                                                          |
      | --effort max                                             |
      | --worktree --task-file task.md --mode local-only         |
      | --worktree --task-file task.md --mode local-only --effort low  |

  Scenario: Name the provider and model of a refused selection
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only --model openrouter/anthropic/claude-opus-5.5
      """
    Then the refusal names provider "openrouter" and model "anthropic/claude-opus-5.5" as unlisted

  Scenario Outline: Fail closed on an unusable allowlist before provisioning
    Given the allowlist is <state>
    When I run riddim with:
      """
      start worker <flags>
      """
    Then start refuses before creating any worker assets or invoking Herdr

    Examples:
      | state                  | flags                                                                                    |
      | missing                |                                                                                          |
      | missing                | --worktree --task-file task.md --mode local-only --model claude-bridge/claude-opus-5-5   |
      | a directory            | --worktree --task-file task.md --mode local-only                                         |
      | empty                  | --worktree --task-file task.md --mode local-only                                         |
      | comments only          | --worktree --task-file task.md --mode local-only --model claude-bridge/claude-opus-5-5   |
      | a pasted profile line  | --worktree --task-file task.md --mode local-only                                         |
      | an unqualified entry   | --worktree --task-file task.md --mode local-only                                         |
      | invalid UTF-8          | --worktree --task-file task.md --mode local-only                                         |

  Scenario Outline: Explain how to fix an unusable allowlist
    Given the allowlist is <state>
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only
      """
    Then the refusal reports "<problem>" for the configured allowlist

    Examples:
      | state                 | problem                                                                          |
      | missing               | missing model allowlist: list one approved provider/model ID per line            |
      | a directory           | unreadable model allowlist: Is a directory                                       |
      | empty                 | empty model allowlist: list one approved provider/model ID per line              |
      | a pasted profile line | malformed model allowlist line 2: expected one provider/model ID without spaces  |
      | invalid UTF-8         | malformed model allowlist: valid UTF-8 is required                               |
