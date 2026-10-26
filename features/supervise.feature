Feature: Start a Riddim supervisor in the current Herdr pane

  Background:
    Given a config directory with agent profile:
      """
      pi openrouter/z-ai/glm-5.3-flash max
      """
    And Herdr reports a running supported server
    And a fake supervisor Pi executable

  Scenario: Launch Pi with the profile, role contract, extension, and selected state directory
    When I run riddim with:
      """
      supervise
      """
    Then Pi receives the supervisor launch arguments and selected state directory

  Scenario: Deliver proactive retirement policy with its safety boundaries to Pi
    When I run riddim with:
      """
      supervise
      """
    Then Pi receives supervisor retirement instructions:
      | instruction                                                                                                    |
      | retire the worker without asking for redundant cleanup consent                                                  |
      | Reconcile already-landed completed workers on later notifications and fleet checks                               |
      | A done report, native idle, or sequence 0 attention alone authorizes neither landing nor cleanup                  |
      | Retain workers with active follow-up or a consumer dependency                                                    |
      | Verify the retained evidence exists and is readable outside the checkout                                         |
      | Stop only exact owned services proven no longer needed after checking their consumers                           |
      | Report the precise blocker and retain assets on a refusal                                                        |
      | A remote PR merge alone does not satisfy local teardown guards                                                   |
      | Never force, reset, stash, modify a dirty user main, delete assets by hand, or clear status gates just to retire   |
      | For a genuinely finished, unneeded worker whose safe termination is proven, use ordinary `riddim exit <name>`     |
      | Report stopped, not retired                                                                                     |
      | Do not auto-stop active follow-up or unreported idle workers                                                      |

  Scenario: Deliver supervisor-owned follow-through without expanding human authority
    When I run riddim with:
      """
      supervise
      """
    Then Pi receives supervisor follow-through instructions:
      | instruction                                                                                                                                 |
      | On notifications and fleet checks, carry out already-authorized review and investigation                                                    |
      | answer worker questions from the task brief or recorded human instructions                                                                  |
      | For an explicitly reported temporary prerequisite, inspect whether that specific condition has cleared                                      |
      | a reported Unity process releasing a needed resource                                                                                        |
      | When verified clear, use `riddim send <name>` to steer continuation within the existing task                                                |
      | If still pending or unverifiable, report the wait and uncertainty without inventing a human decision                                        |
      | This is event-driven follow-through, not a periodic liveness loop or a CI watcher                                                           |
      | For evidenced confusion or looping, inspect first, then use `riddim interrupt <name>` only with a safe corrective instruction               |
      | Slow tests, native idle, and unknown or stopped endpoints alone do not justify interruption, restart, or teardown                           |
      | If safe steering cannot continue the task, retain work and report the precise blocker; Riddim has no relaunch API                           |
      | Legal consent, credentials or device unlock, publication authority, exact-head landing approval, and destructive changes remain human gates |
      | Follow the existing review/landing and repository publication procedures                                                                    |
      | Routine review, investigation, answers, waits and steering stay visible in outcome reports without redundant human gates                    |
      | Reports and notification acknowledgements grant no new permission                                                                           |

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

  Scenario: Let the supervisor Pi run bare riddim commands from this checkout
    When I run riddim with:
      """
      supervise
      """
    Then the supervisor Pi resolves riddim to this checkout's CLI

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
