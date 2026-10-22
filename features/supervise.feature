Feature: Start a Riddim supervisor in the current Herdr pane

  Background:
    Given a config directory with agent profile:
      """
      pi openrouter/z-ai/glm-5.3-flash max
      """
    And Herdr reports a running supported server
    And a fake Pi executable that supports regular TUI mode

  Scenario: Launch Pi with the profile, role contract, extension, and selected state directory
    When I run riddim with:
      """
      supervise
      """
    Then Pi receives the supervisor launch arguments and selected state directory

  Scenario: Select the repository state directory when no override is set
    Given no explicit Riddim state directory
    When I run riddim with:
      """
      supervise
      """
    Then Pi receives the supervisor launch arguments and default state directory

  Scenario: Preserve the current Herdr session without creating or focusing a workspace
    Given the Herdr session is "lab"
    When I run riddim with:
      """
      supervise
      """
    Then Herdr is queried only for the running status of session "lab"

  Scenario: Omit regular TUI mode when Pi does not advertise it
    Given a fake Pi executable without regular TUI mode
    When I run riddim with:
      """
      supervise
      """
    Then Pi receives the supervisor launch arguments without a TUI mode

  Scenario: Refuse an extra argument before checking prerequisites
    When I run riddim with:
      """
      supervise extra
      """
    Then the supervisor command reports its usage and invokes neither Herdr nor Pi

  Scenario: Refuse a missing profile before checking Herdr or launching Pi
    Given no agent profile in the config directory
    When I run riddim with:
      """
      supervise
      """
    Then the supervisor reports the missing profile before invoking Herdr or Pi

  Scenario: Refuse an unreachable Herdr session without launching Pi
    Given Herdr cannot be reached
    When I run riddim with:
      """
      supervise
      """
    Then the supervisor reports that Herdr is unreachable and does not launch Pi

  Scenario: Refuse a stopped Herdr server without launching Pi
    Given Herdr reports a stopped server
    When I run riddim with:
      """
      supervise
      """
    Then the supervisor reports that Herdr is not ready and does not launch Pi

  Scenario: Refuse a symlinked state directory without launching Pi
    Given the selected Riddim state directory is a symlink
    When I run riddim with:
      """
      supervise
      """
    Then the supervisor refuses a symlinked state directory without launching Pi
