Feature: Interrupt a started Pi agent

  Interrupt is lifecycle control, separate from conversational send. It accepts
  only a Riddim-owned name, locks and re-resolves that name, delivers exactly
  one Escape to the exact recorded pane and session, and re-reads that pane's
  Herdr registration afterwards. It never exposes arbitrary keys.

  Rule: One Escape is delivered to the exact recorded endpoint

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr registers pane "w9:p1" as Pi and accepts its interrupt key

    Scenario: Read, interrupt, and re-read the exact pane
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr receives "--session riddim agent get w9:p1" then "--session riddim pane send-keys w9:p1 escape" then "--session riddim agent get w9:p1"

    Scenario: Exit successfully after verified delivery
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command succeeds

    Scenario: Name the pane with the registration re-read and unconfirmed liveness
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard output is "interrupt delivered to pane w9:p1 (Pi registration re-read; process liveness and cancellation unconfirmed)"

    Scenario: Write no error after verified delivery
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error is empty

  Rule: The recorded session overrides the ambient session

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr registers pane "w9:p1" as Pi and accepts its interrupt key
      And the Herdr session is "ambient"

    Scenario: Use only the recorded session
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr receives "--session riddim agent get w9:p1" then "--session riddim pane send-keys w9:p1 escape" then "--session riddim agent get w9:p1"

  Rule: The per-name lock covers delivery and verification

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Keep lifecycle writers serialized while delivering the key
      Given Herdr verifies the per-name lock while interrupting "worker"
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command succeeds

    Scenario: Release the lock after success
      Given Herdr registers pane "w9:p1" as Pi and accepts its interrupt key
      When I run riddim with:
        """
        interrupt worker
        """
      Then the per-name lock for "worker" is available

    Scenario: Let the Herdr child retain the lock after an abrupt controller exit
      Given Herdr verifies inherited ownership of the lock after killing the interrupt controller for "worker"
      When I run riddim with:
        """
        interrupt worker
        """
      Then the Herdr child retained the per-name lock after its controller exited

    Scenario: Release the inherited lock when the Herdr child exits
      Given Herdr verifies inherited ownership of the lock after killing the interrupt controller for "worker"
      When I run riddim with:
        """
        interrupt worker
        """
      Then the inherited per-name lock for "worker" eventually becomes available

  Rule: Missing ownership is refused before Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Invoke no Herdr command
      When I run riddim with:
        """
        interrupt ghost
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        interrupt ghost
        """
      Then the command exits with status 1

    Scenario: Name the missing record
      When I run riddim with:
        """
        interrupt ghost
        """
      Then the missing record refusal is explained for "ghost"

  Rule: Invalid ownership is refused before Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Refuse a malformed record
      Given an existing endpoint record for "worker" that is not a record
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr receives no invocation

    Scenario: Refuse a symlinked record
      Given a symlinked endpoint record for "worker" that points elsewhere
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr receives no invocation

    Scenario: Refuse inconsistent endpoint fields
      Given an endpoint record for "worker" whose window names another pane
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr receives no invocation

    Scenario: Refuse malformed endpoint atoms
      Given an endpoint record for "worker" with a malformed Herdr session
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr receives no invocation

    Scenario: Refuse invalid UTF-8
      Given an endpoint record for "worker" that is not valid UTF-8
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr receives no invocation

  Rule: Only Pi at the exact recorded pane is interrupted

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Refuse a non-Pi registration
      Given Herdr registers pane "w9:p1" as "codex"
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error is "riddim: invalid Herdr agent JSON: expected result.agent.agent to be \"pi\", got \"codex\""

    Scenario: Send no key to a non-Pi registration
      Given Herdr registers pane "w9:p1" as "codex"
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr never sends an interrupt key

    Scenario: Refuse a registration without a pane id
      Given Herdr registers Pi at pane "w9:p1" without a pane id
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error is "riddim: invalid Herdr agent JSON: expected result.agent.pane_id to be a nonempty string"

    Scenario: Refuse a registration that redirects to another pane
      Given Herdr registration at pane "w9:p1" names pane "w9:p2"
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error is "riddim: invalid Herdr agent JSON: expected result.agent.pane_id to equal recorded pane \"w9:p1\", got \"w9:p2\""

    Scenario: Send no key when registration redirects to another pane
      Given Herdr registration at pane "w9:p1" names pane "w9:p2"
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr never sends an interrupt key

  Rule: Herdr signal termination is preserved

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Propagate a pre-delivery read signal
      Given Herdr terminates from signal "TERM" while reading the recorded pane
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command is terminated by signal "TERM"

    Scenario: Preserve captured streams while propagating a signal
      Given Herdr writes captured output then terminates from signal "TERM" while reading the recorded pane
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command preserves signal "TERM", output "partial read", and error "herdr interrupted"

    Scenario: Propagate a delivery signal
      Given Herdr terminates from signal "TERM" while sending the recorded interrupt key
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command is terminated by signal "TERM"

    Scenario: Release the lock after signaled delivery
      Given Herdr terminates from signal "TERM" while sending the recorded interrupt key
      When I run riddim with:
        """
        interrupt worker
        """
      Then the per-name lock for "worker" is available

  Rule: A failed pre-delivery read is preserved

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr fails to read the recorded pane with status 17 and error "herdr: agent not found"

    Scenario: Propagate Herdr's failure status
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command exits with status 17

    Scenario: Propagate Herdr's error
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error is "herdr: agent not found"

    Scenario: Send no key without a verified registration
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr never sends an interrupt key

  Rule: A failed delivery is preserved

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr fails to send the recorded interrupt key with status 7 and error "herdr: pane not found"

    Scenario: Propagate Herdr's failure status
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command exits with status 7

    Scenario: Propagate Herdr's error
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error is "herdr: pane not found"

    Scenario: Write no output when delivery fails
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard output is empty

    Scenario: Release the lock after failed delivery
      When I run riddim with:
        """
        interrupt worker
        """
      Then the per-name lock for "worker" is available

  Rule: A malformed pre-delivery response is refused

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr returns malformed JSON when reading the recorded pane

    Scenario: Reject malformed JSON
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command exits with status 1

    Scenario: Explain malformed JSON
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error is "riddim: invalid Herdr agent JSON: malformed JSON"

    Scenario: Send no key after malformed JSON
      When I run riddim with:
        """
        interrupt worker
        """
      Then Herdr never sends an interrupt key

  Rule: A delivery that cannot be re-verified is reported honestly

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr cannot re-read the recorded pane after the key with status 5 and error "herdr: pane not found"

    Scenario: Fail after an unprovable delivery
      When I run riddim with:
        """
        interrupt worker
        """
      Then the command exits with status 1

    Scenario: Report that the key may have been delivered
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error includes "may have been delivered to pane w9:p1"

    Scenario: Tell the user not to retry blindly
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error includes "do not retry blindly"

    Scenario: Preserve Herdr's re-read failure in the report
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error includes "herdr: pane not found"

    Scenario: Release the lock after an unverified delivery
      When I run riddim with:
        """
        interrupt worker
        """
      Then the per-name lock for "worker" is available

  Rule: A changed post-delivery registration is reported honestly

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Refuse a pane that changed agent kind
      Given Herdr reports the recorded pane hosting "codex" after the key
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error includes "got \"codex\""

    Scenario: Refuse a pane id that changed
      Given Herdr reports pane "w9:p2" for the recorded pane after the key
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error includes "may have been delivered to pane w9:p1"

    Scenario: Refuse a malformed re-read
      Given Herdr replies to the recorded pane re-read with malformed JSON
      When I run riddim with:
        """
        interrupt worker
        """
      Then standard error includes "may have been delivered to pane w9:p1"

  Rule: Exactly one valid owned name is accepted

    Scenario: Reject a missing name
      When I run riddim with:
        """
        interrupt
        """
      Then standard error is "Usage: riddim interrupt <name>"

    Scenario: Reject extra arguments
      When I run riddim with:
        """
        interrupt worker extra
        """
      Then the command exits with status 2

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        interrupt worker extra
        """
      Then standard error is "Usage: riddim interrupt <name>"

    Scenario: Reject an explicit pane id
      When I run riddim with:
        """
        interrupt w9:p1
        """
      Then the command exits with status 2

    Scenario: Explain the owned-name requirement
      When I run riddim with:
        """
        interrupt Worker
        """
      Then standard error is "riddim: name must match [a-z][a-z0-9_-]{0,31}"
