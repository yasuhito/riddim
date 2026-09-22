Feature: Interrupt a Pi agent

  Interrupt is lifecycle control, separate from the conversational send: one
  allowlisted operation that resolves the target once, delivers exactly one
  Escape to the agent's exact pane, and verifies the same Pi endpoint
  afterwards. It never sends arbitrary keys.

  Rule: One Escape is delivered to the resolved pane

    Background:
      Given Herdr resolves pi to pane "w9:p1" and accepts the interrupt key

    Scenario: Resolve the agent then send one Escape and re-verify it
      When I run riddim with:
        """
        interrupt pi
        """
      Then Herdr receives "--session default agent get pi" then "--session default agent send-keys w9:p1 esc" then "--session default agent get w9:p1"

    Scenario: Deliver through a named session
      Given the Herdr session is "lab"
      When I run riddim with:
        """
        interrupt pi
        """
      Then Herdr receives "--session lab agent get pi" then "--session lab agent send-keys w9:p1 esc" then "--session lab agent get w9:p1"

    Scenario: Exit successfully after verified delivery
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command succeeds

    Scenario: Name the pane with the endpoint verified and cancellation unconfirmed
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard output is "interrupt delivered to pane w9:p1 (endpoint verified; cancellation unconfirmed)"

    Scenario: Write no error after verified delivery
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error is empty

  Rule: A target may be a pane id

    Background:
      Given Herdr resolves pi to pane "w9:p1" and accepts the interrupt key

    Scenario: Send the Escape to the same pane
      When I run riddim with:
        """
        interrupt w9:p1
        """
      Then Herdr receives "--session default agent get w9:p1" then "--session default agent send-keys w9:p1 esc" then "--session default agent get w9:p1"

  Rule: Only a Pi agent is interrupted

    Background:
      Given Herdr resolves pi to pane "w9:p1" hosting "codex"

    Scenario: Refuse a non-Pi target
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 1

    Scenario: Explain the non-Pi refusal
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error is "riddim: invalid Herdr agent JSON: expected result.agent.agent to be \"pi\", got \"codex\""

    Scenario: Send no key to a non-Pi agent
      When I run riddim with:
        """
        interrupt pi
        """
      Then Herdr never sends an interrupt key

  Rule: The Pi response must carry a pane id

    Background:
      Given Herdr resolves pi without a pane id

    Scenario: Reject a response without a pane id
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 1

    Scenario: Explain the missing pane id
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error is "riddim: invalid Herdr agent JSON: expected result.agent.pane_id to be a nonempty string"

    Scenario: Send no key without a pane id
      When I run riddim with:
        """
        interrupt pi
        """
      Then Herdr never sends an interrupt key

  Rule: A failed resolution is preserved

    Background:
      Given Herdr fails with status 17 and error "herdr: agent not found"

    Scenario: Propagate Herdr's failure status
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 17

    Scenario: Propagate Herdr's error
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error is "herdr: agent not found"

    Scenario: Send no key without a resolved agent
      When I run riddim with:
        """
        interrupt pi
        """
      Then Herdr never sends an interrupt key

  Rule: A failed delivery is preserved

    Background:
      Given Herdr fails to send the interrupt key with status 7 and error "herdr: pane not found"

    Scenario: Propagate Herdr's failure status
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 7

    Scenario: Propagate Herdr's error
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error is "herdr: pane not found"

    Scenario: Write no output when delivery fails
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard output is empty

  Rule: Malformed responses are refused

    Background:
      Given Herdr returns agent JSON:
        """
        not JSON
        """

    Scenario: Reject malformed JSON
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 1

    Scenario: Explain malformed JSON
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error is "riddim: invalid Herdr agent JSON: malformed JSON"

    Scenario: Send no key to a malformed response
      When I run riddim with:
        """
        interrupt pi
        """
      Then Herdr never sends an interrupt key

  Rule: A delivery that cannot be re-verified is reported honestly

    Background:
      Given Herdr cannot re-read pane "w9:p1" after the key with status 5 and error "herdr: pane not found"

    Scenario: Fail after an unprovable delivery
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 1

    Scenario: Report that the key may have been delivered
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error includes "may have been delivered to pane w9:p1"

    Scenario: Tell the user not to retry blindly
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error includes "do not retry blindly"

    Scenario: Preserve Herdr's re-read failure in the report
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error includes "herdr: pane not found"

  Rule: A pane that changed kind is reported honestly

    Background:
      Given Herdr reports pane "w9:p1" hosting "codex" after the key

    Scenario: Fail when the endpoint no longer holds a Pi agent
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 1

    Scenario: Report that the key may have been delivered
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error includes "may have been delivered to pane w9:p1"

    Scenario: Report the changed kind
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error includes "got \"codex\""

  Rule: A pane id that no longer matches is reported honestly

    Background:
      Given Herdr reports pane "w9:p1" in pane "w9:p2" after the key

    Scenario: Fail when the pane id changed
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 1

    Scenario: Report that the key may have been delivered
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error includes "may have been delivered to pane w9:p1"

  Rule: A malformed re-read is reported honestly

    Background:
      Given Herdr replies to the pane re-read with malformed JSON

    Scenario: Fail after a malformed re-read
      When I run riddim with:
        """
        interrupt pi
        """
      Then the command exits with status 1

    Scenario: Report that the key may have been delivered
      When I run riddim with:
        """
        interrupt pi
        """
      Then standard error includes "may have been delivered to pane w9:p1"

  Rule: Exactly one target is accepted

    Scenario: Reject a missing target
      When I run riddim with:
        """
        interrupt
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a target
      When I run riddim with:
        """
        interrupt
        """
      Then standard error is "Usage: riddim interrupt <target>"

    Scenario: Reject extra arguments
      When I run riddim with:
        """
        interrupt pi extra
        """
      Then the command exits with status 2

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        interrupt pi extra
        """
      Then standard error is "Usage: riddim interrupt <target>"