Feature: Start a background Pi agent

  Rule: The command takes exactly one valid agent name

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And a Herdr executable that refuses every invocation

    Scenario: Reject a missing name
      When I run riddim with:
        """
        start
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a name
      When I run riddim with:
        """
        start
        """
      Then standard error is "Usage: riddim start <name>"

    Scenario: Reject extra arguments
      When I run riddim with:
        """
        start worker extra
        """
      Then the command exits with status 2

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        start worker extra
        """
      Then standard error is "Usage: riddim start <name>"

    Scenario: Reject a name Herdr would not accept
      When I run riddim with:
        """
        start Worker
        """
      Then the command exits with status 2

    Scenario: Explain the accepted name shape
      When I run riddim with:
        """
        start Worker
        """
      Then standard error is "riddim: name must match [a-z][a-z0-9_-]{0,31}"

  Rule: The profile must be one supported pi line

    Background:
      Given a Herdr executable that refuses every invocation

    Scenario: Reject a missing profile file
      Given no agent profile in the config directory
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain a missing profile file
      Given no agent profile in the config directory
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: missing profile file: agent-profile"

    Scenario: Invoke no Herdr command for a missing profile
      Given no agent profile in the config directory
      When I run riddim with:
        """
        start worker
        """
      Then Herdr receives no invocation

    Scenario: Reject a profile file without a profile line
      Given a config directory with agent profile:
        """
        # riddim agent profile
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain a profile file without a profile line
      Given a config directory with agent profile:
        """
        # riddim agent profile
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: no profile line in agent-profile"

    Scenario: Reject a short profile line
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain a short profile line
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: malformed profile line: expected \"<harness> <model> <effort>\""

    Scenario: Reject a model with a control character
      Given a config directory with a profile whose model contains a control character
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain a model with a control character
      Given a config directory with a profile whose model contains a control character
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: unsupported model: control characters are not allowed"

    Scenario: Reject an unsupported harness
      Given a config directory with agent profile:
        """
        claude opus high
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain an unsupported harness
      Given a config directory with agent profile:
        """
        claude opus high
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: unsupported harness \"claude\": only \"pi\" is supported"

    Scenario: Reject an unsupported effort
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash ultra
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain an unsupported effort
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash ultra
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: unsupported effort \"ultra\": expected one of off, minimal, low, medium, high, xhigh, max"

    Scenario: Reject a second profile line
      Given a config directory with agent profile:
        """
        pi model max
        pi other-model high
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain a second profile line
      Given a config directory with agent profile:
        """
        pi model max
        pi other-model high
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: expected one profile line in agent-profile, found 2"

  Rule: A valid profile creates an unfocused workspace and starts the agent in its root pane

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and starts the agent

    Scenario: Print a success line with the agent and pane
      When I run riddim with:
        """
        start worker
        """
      Then standard output is "started worker in w9:p1"

    Scenario: Exit successfully
      When I run riddim with:
        """
        start worker
        """
      Then the command succeeds

    Scenario: Write no error
      When I run riddim with:
        """
        start worker
        """
      Then standard error is empty

    Scenario: Create the workspace without focusing it
      When I run riddim with:
        """
        start worker
        """
      Then Herdr creates a workspace labeled "riddim-worker" in the current directory without focus

    Scenario: Start the agent in the root pane with the profile's model and effort
      When I run riddim with:
        """
        start worker
        """
      Then Herdr starts agent "worker" in pane "w9:p1" with model "openrouter/z-ai/glm-5.3-flash" and effort "max"

    Scenario: Do nothing else beyond creating and starting
      When I run riddim with:
        """
        start worker
        """
      Then Herdr only creates the workspace and starts the agent

    Scenario: Create and start through a named session
      Given the Herdr session is "lab"
      When I run riddim with:
        """
        start worker
        """
      Then Herdr creates a workspace and starts the agent in session "lab"

  Rule: An invalid create response is rejected

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """

    Scenario: Reject malformed JSON
      Given Herdr replies to the workspace create with:
        """
        not JSON
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain malformed JSON
      Given Herdr replies to the workspace create with:
        """
        not JSON
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: invalid Herdr workspace JSON: malformed JSON"

    Scenario: Start no agent after a malformed response
      Given Herdr replies to the workspace create with:
        """
        not JSON
        """
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never starts an agent

    Scenario: Reject a create response without a root pane
      Given Herdr replies to the workspace create with:
        """
        {"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1"}}}
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain a create response without a root pane
      Given Herdr replies to the workspace create with:
        """
        {"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1"}}}
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: invalid Herdr workspace JSON: expected workspace, tab, and root_pane ids in the create response"

    Scenario: Start no agent when ids are missing
      Given Herdr replies to the workspace create with:
        """
        {"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1"}}}
        """
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never starts an agent

    Scenario: Reject a contradictory create response
      Given Herdr replies to the workspace create with:
        """
        {"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1","workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1","workspace_id":"w9","tab_id":"w8:t1"}}}
        """
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain a contradictory create response
      Given Herdr replies to the workspace create with:
        """
        {"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1","workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1","workspace_id":"w9","tab_id":"w8:t1"}}}
        """
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "riddim: invalid Herdr workspace JSON: contradictory create response: tab and root pane do not belong to the returned workspace and tab"

    Scenario: Start no agent after a contradictory response
      Given Herdr replies to the workspace create with:
        """
        {"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1","workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1","workspace_id":"w9","tab_id":"w8:t1"}}}
        """
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never starts an agent

  Rule: A failed workspace create is propagated

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr refuses to create a workspace with status 17 and error "herdr: cannot create workspace"

    Scenario: Propagate Herdr's failure status
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 17

    Scenario: Propagate Herdr's error
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "herdr: cannot create workspace"

    Scenario: Start no agent
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never starts an agent

  Rule: A failed agent start rolls back the created pane

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" but fails to start the agent with status 19 and error "herdr: agent not ready"

    Scenario: Propagate the start failure status
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 19

    Scenario: Preserve the start failure error
      When I run riddim with:
        """
        start worker
        """
      Then standard error is "herdr: agent not ready"

    Scenario: Write no output for a failed start
      When I run riddim with:
        """
        start worker
        """
      Then standard output is empty

    Scenario: Close only the created root pane
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes only pane "w9:p1"

    Scenario: Close the created pane through a named session
      Given the Herdr session is "lab"
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes only pane "w9:p1" in session "lab"

    Scenario: A failed rollback does not mask the start failure
      Given Herdr creates workspace "w9" but fails to start the agent with status 19 and error "herdr: agent not ready" and closes panes with status 7
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 19
