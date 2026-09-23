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
      Then standard error is "Usage: riddim start <name> [--worktree [--task-file <path>]]"

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
      Then standard error is "Usage: riddim start <name> [--worktree [--task-file <path>]]"

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
      Then standard error is "riddim: unsupported effort \"ultra\": expected one of low, medium, high, xhigh, max"

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

  Rule: Unsupported Herdr clients are refused before endpoint creation

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and starts the agent
      And the Herdr client reports protocol 13

    Scenario: Reject a client below Firstmate's protocol floor
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never creates a workspace

  Rule: Herdr below the focus-safe release is refused before endpoint creation

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and starts the agent
      And the Herdr client reports version "0.7.5"

    Scenario: Reject a release whose emptying-close can steal focus
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never creates a workspace

    Scenario: Refuse a prerelease that does not guarantee the focus fix
      Given the Herdr client reports version "0.8.0-rc1"
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never creates a workspace

  Rule: An older running Herdr server is refused before endpoint creation

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and starts the agent
      And the running Herdr server reports version "0.7.5"

    Scenario: Reject a focus-unsafe server even with a supported client
      When I run riddim with:
        """
        start worker
        """
      Then Herdr never creates a workspace

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

  Rule: A started agent publishes an exact endpoint ownership record

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and starts the agent

    Scenario: Publish the exact ownership record bytes
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" is:
        """
        window=default:w9:p1
        endpoint_task_id=worker
        harness=pi
        model=openrouter/z-ai/glm-5.3-flash
        effort=max
        spawn_gen=<spawn_gen>
        backend=herdr
        herdr_session=default
        herdr_workspace_id=w9
        herdr_tab_id=w9:t1
        herdr_pane_id=w9:p1
        """

    Scenario: Record the named session's window identity
      Given the Herdr session is "lab"
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" is:
        """
        window=lab:w9:p1
        endpoint_task_id=worker
        harness=pi
        model=openrouter/z-ai/glm-5.3-flash
        effort=max
        spawn_gen=<spawn_gen>
        backend=herdr
        herdr_session=lab
        herdr_workspace_id=w9
        herdr_tab_id=w9:t1
        herdr_pane_id=w9:p1
        """

    Scenario: Record a fresh spawn generation
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" records a fresh spawn generation

    Scenario: Keep the state directory owner-only
      When I run riddim with:
        """
        start worker
        """
      Then the state directory is readable only by its owner

    Scenario: Keep the record owner-only
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" is readable only by its owner

    Scenario: Leave no temporary files beside the record
      When I run riddim with:
        """
        start worker
        """
      Then only the record and its per-name lock remain in the state directory

  Rule: An existing endpoint record refuses a duplicate start before Herdr is invoked

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And a Herdr executable that refuses every invocation
      And an existing endpoint record for "worker" that is not a record

    Scenario: Refuse the duplicate start
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain the duplicate refusal
      When I run riddim with:
        """
        start worker
        """
      Then the duplicate endpoint record refusal is explained for "worker"

    Scenario: Invoke no Herdr command
      When I run riddim with:
        """
        start worker
        """
      Then Herdr receives no invocation

    Scenario: Leave the existing record untouched
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" still is:
        """
        spawn_gen=s1
        not a record
        """

  Rule: The record is published before the agent starts

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and refuses to start an agent before its record exists

    Scenario: Start the agent only after the record is published
      When I run riddim with:
        """
        start worker
        """
      Then the command succeeds

  Rule: A failed record publication rolls back the created endpoint

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" but another writer claims the record during creation

    Scenario: Refuse with Riddim's own failure status
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Explain the refusal and the confirmed cleanup
      When I run riddim with:
        """
        start worker
        """
      Then the publication refusal and the confirmed cleanup are reported for "worker"

    Scenario: Close and re-read the created pane without starting an agent
      When I run riddim with:
        """
        start worker
        """
      Then Herdr creates only the workspace and then closes and re-reads pane "w9:p1"

    Scenario: Leave the other writer's record untouched
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" still is:
        """
        claimed by another writer
        """

  Rule: A failed record publication reports unconfirmed cleanup honestly

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" but another writer claims the record during creation and closes panes with status 7

    Scenario: Refuse with Riddim's own failure status
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Report the unconfirmed cleanup without claiming it
      When I run riddim with:
        """
        start worker
        """
      Then the publication refusal and the unconfirmed cleanup are reported for "worker"

    Scenario: Read the pane only after a successful close
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes the created pane "w9:p1" without a follow-up pane read

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

    Scenario: Publish no record after a malformed response
      Given Herdr replies to the workspace create with:
        """
        not JSON
        """
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" does not exist

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

    Scenario: Publish no record
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" does not exist

  Rule: A failed agent start closes the created pane and removes the record when cleanup is confirmed

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

    Scenario: Close and re-read only the created root pane
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes and re-reads only pane "w9:p1"

    Scenario: Re-read the created pane through a named session
      Given the Herdr session is "lab"
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes and re-reads only pane "w9:p1" in session "lab"

    Scenario: Remove the endpoint record after the confirmed close
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" does not exist

  Rule: A close that fails retains the endpoint record

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" but fails to start the agent with status 19 and error "herdr: agent not ready" and closes panes with status 7

    Scenario: Preserve Herdr's exit status
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 19

    Scenario: Preserve Herdr's error
      When I run riddim with:
        """
        start worker
        """
      Then standard error includes "herdr: agent not ready"

    Scenario: Report the retained record without masking Herdr's failure
      When I run riddim with:
        """
        start worker
        """
      Then Herdr's failure and the retained record are reported for "worker"

    Scenario: Retain the endpoint record
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" remains

    Scenario: Issue only the close when it fails
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes pane "w9:p1" without a follow-up pane read

  Rule: A pane that survives the close retains the endpoint record

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" but fails to start the agent with status 19 and error "herdr: agent not ready" and leaves the pane present

    Scenario: Retain the record while the pane still exists
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" remains

    Scenario: Read the pane once after the close
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes and re-reads only pane "w9:p1"

  Rule: A Herdr executable that vanishes after publication retains the record

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and then disappears

    Scenario: Refuse with Riddim's own failure status
      When I run riddim with:
        """
        start worker
        """
      Then the command exits with status 1

    Scenario: Retain the endpoint record
      When I run riddim with:
        """
        start worker
        """
      Then the endpoint record for "worker" remains

    Scenario: Report the retained record
      When I run riddim with:
        """
        start worker
        """
      Then the unlaunchable Herdr failure and the retained record are reported for "worker"

    Scenario: Issue no pane cleanup without a Herdr executable
      When I run riddim with:
        """
        start worker
        """
      Then Herdr closes no pane without a Herdr executable

  Rule: Two same-name starts serialize on the per-name lock

    Background:
      Given a config directory with agent profile:
        """
        pi openrouter/z-ai/glm-5.3-flash max
        """
      And Herdr creates workspace "w9" and starts the agent

    Scenario: Succeed exactly once
      When I run two riddim starts of "worker" at the same time
      Then exactly one of the two starts succeeds

    Scenario: Refuse the losing start as a duplicate
      When I run two riddim starts of "worker" at the same time
      Then the losing start refuses the duplicate for "worker"

    Scenario: Create exactly one workspace
      When I run two riddim starts of "worker" at the same time
      Then Herdr creates the workspace exactly once

    Scenario: Start exactly one agent
      When I run two riddim starts of "worker" at the same time
      Then Herdr starts exactly one agent
