Feature: Read a started agent's registered Herdr status

  Status resolves the agent's endpoint ownership record and asks Herdr for the
  registration attached to that exact recorded pane and session. The printed
  value is only Herdr's raw agent_status, not Firstmate's recovery-grade
  current crew state, process liveness, or current task activity.

  Rule: Status is read from the recorded agent registration

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr returns agent JSON for pane "w9:p1":
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi","agent_status":"working","pane_id":"w9:p1"}}}
        """

    Scenario: Print the raw registration status
      When I run riddim with:
        """
        status worker
        """
      Then standard output is "working"

    Scenario: Exit successfully after reading the status
      When I run riddim with:
        """
        status worker
        """
      Then the command succeeds

    Scenario: Write no error after reading the status
      When I run riddim with:
        """
        status worker
        """
      Then standard error is empty

    Scenario: Address the exact recorded pane and session
      When I run riddim with:
        """
        status worker
        """
      Then Herdr is invoked with "--session riddim agent get w9:p1"

  Rule: The recorded session overrides the ambient session

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr returns agent JSON for pane "w9:p1":
        """
        {"result":{"agent":{"agent_status":"idle"}}}
        """
      And the Herdr session is "ambient"

    Scenario: Target the recorded session, not the ambient one
      When I run riddim with:
        """
        status worker
        """
      Then Herdr is invoked with "--session riddim agent get w9:p1"

  Rule: A missing record is refused before Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        status ghost
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        status ghost
        """
      Then the command exits with status 1

    Scenario: Name the missing record
      When I run riddim with:
        """
        status ghost
        """
      Then the missing record refusal is explained for "ghost"

  Rule: A malformed record is refused before Herdr

    Background:
      Given a fake Herdr executable
      And an existing endpoint record for "worker" that is not a record

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        status worker
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        status worker
        """
      Then the command exits with status 1

  Rule: A record with invalid text encoding is refused before Herdr

    Background:
      Given a fake Herdr executable
      And an endpoint record for "worker" that is not valid UTF-8

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        status worker
        """
      Then Herdr receives no invocation

    Scenario: Explain the controlled refusal without a backtrace
      When I run riddim with:
        """
        status worker
        """
      Then the invalid UTF-8 record refusal is explained for "worker"

  Rule: A symlinked record is refused before Herdr

    Background:
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere

    Scenario: Fail closed without following the link
      When I run riddim with:
        """
        status worker
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        status worker
        """
      Then the command exits with status 1

  Rule: Inconsistent endpoint metadata is refused before Herdr

    Background:
      Given a fake Herdr executable
      And an endpoint record for "worker" whose window names another pane

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        status worker
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        status worker
        """
      Then the command exits with status 1

  Rule: Malformed Herdr endpoint ids are refused before Herdr

    Background:
      Given a fake Herdr executable
      And an endpoint record for "worker" with a malformed Herdr session

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        status worker
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's refusal status
      When I run riddim with:
        """
        status worker
        """
      Then the command exits with status 1

  Rule: Herdr command failures are preserved

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And the recorded agent read fails with status 17, output "partial agent response", and error "herdr: agent not found"

    Scenario: Propagate Herdr's failure status
      When I run riddim with:
        """
        status worker
        """
      Then the command exits with status 17

    Scenario: Preserve Herdr's error
      When I run riddim with:
        """
        status worker
        """
      Then standard error is "herdr: agent not found"

    Scenario: Preserve Herdr's partial output
      When I run riddim with:
        """
        status worker
        """
      Then standard output is "partial agent response"

  Rule: Invalid Herdr output is rejected clearly

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"

    Scenario: Reject malformed JSON
      Given Herdr returns agent JSON for pane "w9:p1":
        """
        not JSON
        """
      When I run riddim with:
        """
        status worker
        """
      Then the command exits with status 1

    Scenario: Explain malformed JSON
      Given Herdr returns agent JSON for pane "w9:p1":
        """
        not JSON
        """
      When I run riddim with:
        """
        status worker
        """
      Then standard error is "riddim: invalid Herdr agent JSON: malformed JSON"

    Scenario: Reject JSON without a status
      Given Herdr returns agent JSON for pane "w9:p1":
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi"}}}
        """
      When I run riddim with:
        """
        status worker
        """
      Then the command exits with status 1

    Scenario: Explain JSON without a status
      Given Herdr returns agent JSON for pane "w9:p1":
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi"}}}
        """
      When I run riddim with:
        """
        status worker
        """
      Then standard error is "riddim: invalid Herdr agent JSON: expected result.agent.agent_status to be idle, working, blocked, done, or unknown"

  Rule: The command accepts exactly one started-agent name

    Scenario: Reject a missing name
      When I run riddim with:
        """
        status
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a name
      When I run riddim with:
        """
        status
        """
      Then standard error is "Usage: riddim status <name>"

    Scenario: Reject extra arguments
      When I run riddim with:
        """
        status worker extra
        """
      Then the command exits with status 2

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        status worker extra
        """
      Then standard error is "Usage: riddim status <name>"

    Scenario: Reject a name outside the agent-name shape
      When I run riddim with:
        """
        status Worker
        """
      Then the command exits with status 2

    Scenario: Explain the agent-name shape
      When I run riddim with:
        """
        status Worker
        """
      Then standard error is "riddim: name must match [a-z][a-z0-9_-]{0,31}"
