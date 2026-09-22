Feature: Read an agent's status

  The printed value is Herdr's raw agent registration status. It does not
  prove the agent's process is alive or its current task state.

  Rule: Status is read from Herdr

    Scenario: Print the agent status
      Given Herdr returns agent JSON:
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi","agent_status":"working"}}}
        """
      When I run riddim with:
        """
        status pi
        """
      Then standard output is "working"

    Scenario: Exit successfully after reading the status
      Given Herdr returns agent JSON:
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi","agent_status":"working"}}}
        """
      When I run riddim with:
        """
        status pi
        """
      Then the command succeeds

    Scenario: Write no error after reading the status
      Given Herdr returns agent JSON:
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi","agent_status":"working"}}}
        """
      When I run riddim with:
        """
        status pi
        """
      Then standard error is empty

  Rule: Exactly one target is required

    Scenario: Reject a missing target
      When I run riddim with:
        """
        status
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a target
      When I run riddim with:
        """
        status
        """
      Then standard error is "Usage: riddim status <target>"

    Scenario: Reject extra arguments
      When I run riddim with:
        """
        status pi extra
        """
      Then the command exits with status 2

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        status pi extra
        """
      Then standard error is "Usage: riddim status <target>"

  Rule: Herdr command failures are preserved

    Scenario: Propagate Herdr's failure status
      Given Herdr fails with status 17 and error "herdr: agent not found"
      When I run riddim with:
        """
        status pi
        """
      Then the command exits with status 17

    Scenario: Propagate Herdr's error
      Given Herdr fails with status 17 and error "herdr: agent not found"
      When I run riddim with:
        """
        status pi
        """
      Then standard error is "herdr: agent not found"

  Rule: Invalid Herdr output is rejected clearly

    Scenario: Reject malformed JSON
      Given Herdr returns agent JSON:
        """
        not JSON
        """
      When I run riddim with:
        """
        status pi
        """
      Then the command exits with status 1

    Scenario: Explain malformed JSON
      Given Herdr returns agent JSON:
        """
        not JSON
        """
      When I run riddim with:
        """
        status pi
        """
      Then standard error is "riddim: invalid Herdr agent JSON: malformed JSON"

    Scenario: Reject JSON without a status
      Given Herdr returns agent JSON:
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi"}}}
        """
      When I run riddim with:
        """
        status pi
        """
      Then the command exits with status 1

    Scenario: Explain JSON without a status
      Given Herdr returns agent JSON:
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi"}}}
        """
      When I run riddim with:
        """
        status pi
        """
      Then standard error is "riddim: invalid Herdr agent JSON: expected result.agent.agent_status to be idle, working, blocked, done, or unknown"

  Rule: The agent is read in the resolved session

    Scenario: Read the agent through a named session
      Given the Herdr session is "lab"
      And Herdr returns agent JSON:
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi","agent_status":"working"}}}
        """
      When I run riddim with:
        """
        status pi
        """
      Then Herdr is invoked with "--session lab agent get pi"

    Scenario: Read the agent through the default session
      Given Herdr returns agent JSON:
        """
        {"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi","agent_status":"working"}}}
        """
      When I run riddim with:
        """
        status pi
        """
      Then Herdr is invoked with "--session default agent get pi"
