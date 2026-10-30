Feature: Select a Pi model and effort for one worker

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
      Delivery contract: mode=local-only
      Complete the local task.
      """

  Scenario Outline: Task launch and metadata share the effective profile
    Given Pi records its exact launch arguments and profile
    When I run riddim with:
      """
      start worker <flags>
      """
    Then Pi and the ownership record select model "<model>" and effort "<effort>" without changing config

    Examples:
      | flags                                                                                           | model                            | effort |
      | --worktree --task-file task.md --mode local-only --model provider/model --effort high              | provider/model                   | high   |
      | --effort=medium --mode=local-only --task-file=task.md --model=provider/model --worktree              | provider/model                   | medium |
      | --worktree --task-file task.md --mode local-only                                                  | openrouter/z-ai/glm-5.3-flash      | max    |
      | --model provider/model --mode local-only --worktree --task-file task.md                            | provider/model                   | max    |
      | --effort xhigh --worktree --mode local-only --task-file task.md                                    | openrouter/z-ai/glm-5.3-flash      | xhigh  |
      | --worktree --task-file task.md --model 'provider/a;$(touch PWNED)`touch PWNED`' --effort high   | provider/a;$(touch PWNED)`touch PWNED` | high |
      | --worktree --task-file task.md --model "provider/a'b = c" --effort low                             | provider/a'b = c                 | low    |

  Scenario: Coexisting native workers keep independent profiles and leave defaults intact
    Given Herdr records exact native agent arguments for distinct endpoints
    When I start two differently configured workers and then a default worker
    Then all three native launches match their independent recorded profiles

  Scenario Outline: Reject malformed options before provisioning
    When I run riddim with:
      """
      start worker <flags>
      """
    Then start refuses before creating any worker assets or invoking Herdr

    Examples:
      | flags                                                                                          |
      | --worktree --task-file task.md --model                                                          |
      | --worktree --task-file task.md --effort                                                         |
      | --worktree --task-file task.md --model=                                                         |
      | --worktree --task-file task.md --effort=                                                        |
      | --worktree --task-file task.md --model ''                                                       |
      | --worktree --task-file task.md --effort ''                                                      |
      | --worktree --task-file task.md --model a --model=b                                              |
      | --worktree --task-file task.md --effort high --effort=low                                       |
      | --worktree --worktree --task-file task.md --model a                                             |
      | --worktree --task-file task.md --task-file=task.md --model a                                    |
      | --worktree --task-file task.md --mode local-only --mode=local-only --model a                     |
      | --worktree --task-file task.md --effort ultra                                                   |
      | --worktree --task-file task.md --effort HIGH                                                    |
      | --worktree --task-file task.md --model a --unknown b                                            |
      | --worktree --task-file task.md --model a extra                                                  |
      | --task-file task.md --model a                                                                  |
      | --mode local-only --model a                                                                    |
      | --worktree --mode local-only --effort high                                                      |
      | --worktree --task-file task.md --mode remote --model a                                          |
      | --worktree=true --task-file task.md --model a                                                   |
      | --worktree --task-file task.md --model --effort high                                            |
      | --worktree --task-file task.md --model=--other-option                                           |

  Scenario Outline: Refuse control characters and invalid model bytes
    When I try a model containing "<kind>"
    Then start refuses before creating any worker assets or invoking Herdr

    Examples:
      | kind            |
      | newline         |
      | carriage return |
      | tab             |
      | escape          |
      | delete          |
      | empty           |
      | invalid UTF-8   |

  Scenario: Overrides do not replace required configuration
    Given no agent profile in the config directory
    When I run riddim with:
      """
      start worker --model provider/model --effort high --worktree --task-file task.md --mode local-only
      """
    Then start refuses before creating any worker assets or invoking Herdr

  Scenario: Overrides do not bypass configured effort validation
    Given a config directory with agent profile:
      """
      pi provider/model ultra
      """
    When I run riddim with:
      """
      start worker --model provider/model --effort high --worktree --task-file task.md --mode local-only
      """
    Then start refuses before creating any worker assets or invoking Herdr

  Scenario: Overrides do not bypass the task's local-only delivery gate
    Given a task file containing:
      """
      Delivery contract: mode=remote
      Publish this task.
      """
    When I run riddim with:
      """
      start worker --worktree --task-file task.md --mode local-only --model provider/model --effort high
      """
    Then start refuses before creating any worker assets or invoking Herdr
