Feature: Send a direct prompt to a started agent

  Send resolves the agent's endpoint ownership record and submits one direct
  Herdr native prompt to the exact recorded pane and session. It deliberately
  remains smaller than Firstmate's durable steering inbox and reply tracking.

  Rule: A valid message is sent to the recorded endpoint

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a fake Herdr executable

    Scenario: Address the exact recorded pane and session
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then Herdr receives "--session riddim agent prompt w9:p1 Fix the tests"

    Scenario: Exit successfully
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command succeeds

    Scenario: Write no error
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then standard error is empty

  Rule: The per-name lock remains held through prompt completion

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Keep lifecycle writers serialized while Herdr handles the prompt
      Given the recorded prompt observes whether the lock for "worker" is held
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then standard output is "prompt observed held lock"

    Scenario: Keep the lock in Herdr after the controller is killed
      Given Herdr retains the send lock after the controller dies for "worker"
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the Herdr send child retained the lock after controller death

    Scenario: Release the lock after a successful prompt
      Given a fake Herdr executable
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the per-name lock for "worker" is available

  Rule: The recorded session overrides the ambient session

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a fake Herdr executable
      And the Herdr session is "ambient"

    Scenario: Target the recorded session, not the ambient one
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then Herdr is invoked with "--session riddim agent prompt w9:p1 Fix the tests"

  Rule: A later --wait stays message text

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a fake Herdr executable

    Scenario: Keep a later wait flag in an ordinary message
      When I run riddim with:
        """
        send worker try --wait
        """
      Then Herdr receives "--session riddim agent prompt w9:p1 try --wait"

  Rule: A missing record is refused before Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        send ghost Fix the tests
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        send ghost Fix the tests
        """
      Then the command exits with status 1

    Scenario: Name the missing record
      When I run riddim with:
        """
        send ghost Fix the tests
        """
      Then the missing record refusal is explained for "ghost"

  Rule: A malformed record is refused before Herdr

    Background:
      Given a fake Herdr executable
      And an existing endpoint record for "worker" that is not a record

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command exits with status 1

  Rule: A symlinked record is refused before Herdr

    Background:
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere

    Scenario: Fail closed without following the link
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command exits with status 1

  Rule: Inconsistent endpoint metadata is refused before Herdr

    Background:
      Given a fake Herdr executable
      And an endpoint record for "worker" whose window names another pane

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command exits with status 1

  Rule: Malformed Herdr endpoint ids are refused before Herdr

    Background:
      Given a fake Herdr executable
      And an endpoint record for "worker" with a malformed Herdr session

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command exits with status 1

  Rule: Herdr prompt failure is completion-unknown, not proof of non-delivery

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And the recorded prompt fails with status 17, output "partial prompt response", and error "herdr: agent not found"

    Scenario: Return a distinct completion-unknown status
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command exits with status 3

    Scenario: Preserve Herdr's error
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then standard error includes "herdr: agent not found"

    Scenario: Warn against a blind retry after a failed prompt
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then standard error includes "prompt delivery is unconfirmed; inspect the pane before retrying"

    Scenario: Preserve Herdr's partial output
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then standard output is "partial prompt response"

    Scenario: Release the lock after a failed prompt
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the per-name lock for "worker" is available

  Rule: Process-level prompt failures preserve their execution semantics

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Propagate a terminating signal
      Given the recorded prompt terminates from signal "TERM"
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command is terminated by signal "TERM"

    Scenario: Forward controller termination to Herdr and preserve its signal
      Given the recorded prompt sends signal "TERM" to its controller
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command is terminated by signal "TERM"

    Scenario: Release the lock after a signaled prompt
      Given the recorded prompt terminates from signal "TERM"
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the per-name lock for "worker" is available

    Scenario: Report an unavailable Herdr executable as Riddim's failure
      Given no Herdr executable is available
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the command exits with status 1

    Scenario: Release the lock when Herdr cannot be started
      Given no Herdr executable is available
      When I run riddim with:
        """
        send worker Fix the tests
        """
      Then the per-name lock for "worker" is available

  Rule: send --wait is rejected without invoking Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Reject a send --wait invocation
      When I run riddim with:
        """
        send --wait worker Fix the tests
        """
      Then the command exits with status 2

    Scenario: Explain that send --wait is unsupported
      When I run riddim with:
        """
        send --wait worker Fix the tests
        """
      Then standard error is "riddim: send --wait is unsupported; use riddim send <name> <message...>"

    Scenario: Reject a bare send --wait the same way
      When I run riddim with:
        """
        send --wait
        """
      Then standard error is "riddim: send --wait is unsupported; use riddim send <name> <message...>"

    Scenario: Invoke no Herdr command for a rejected send --wait
      When I run riddim with:
        """
        send --wait worker Fix the tests
        """
      Then Herdr receives no invocation

  Rule: A name and a message are required

    Scenario: Reject a missing name
      When I run riddim with:
        """
        send
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a name
      When I run riddim with:
        """
        send
        """
      Then standard error is "Usage: riddim send <name> <message...>"

    Scenario: Reject a missing message
      When I run riddim with:
        """
        send worker
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a message
      When I run riddim with:
        """
        send worker
        """
      Then standard error is "Usage: riddim send <name> <message...>"

    Scenario: Reject a name outside the agent-name shape
      When I run riddim with:
        """
        send Worker Fix the tests
        """
      Then the command exits with status 2

    Scenario: Explain the agent-name shape
      When I run riddim with:
        """
        send Worker Fix the tests
        """
      Then standard error is "riddim: name must match [a-z][a-z0-9_-]{0,31}"

  Rule: A blank message is invalid

    Scenario: Reject a blank message
      When I run riddim with:
        """
        send worker "   "
        """
      Then the command exits with status 2

    Scenario: Write no output for a blank message
      When I run riddim with:
        """
        send worker "   "
        """
      Then standard output is empty

    Scenario: Explain that a blank message is invalid
      When I run riddim with:
        """
        send worker "   "
        """
      Then standard error is "riddim: message must not be blank"
