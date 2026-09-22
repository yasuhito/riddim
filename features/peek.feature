Feature: Read a started agent's recent output

  peek resolves the agent's endpoint ownership record and captures the exact
  Herdr pane it binds, in the session the record names, with Firstmate's
  Herdr capture: a generous recent pane read trimmed locally to the
  requested tail.

  Rule: The recorded endpoint is captured exactly

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a Herdr executable that answers a pane read with 250 lines

    Scenario: Fetch at least two hundred recent lines for a smaller tail
      When I run riddim with:
        """
        peek worker 5
        """
      Then Herdr is invoked with "--session riddim pane read w9:p1 --source recent --lines 200"

    Scenario: Fetch exactly the requested tail above the minimum
      When I run riddim with:
        """
        peek worker 250
        """
      Then Herdr is invoked with "--session riddim pane read w9:p1 --source recent --lines 250"

    Scenario: Print the final requested lines of the capture
      When I run riddim with:
        """
        peek worker 3
        """
      Then standard output is the final 3 lines of the pane read

    Scenario: Exit successfully after the capture
      When I run riddim with:
        """
        peek worker 3
        """
      Then the command succeeds

    Scenario: Write no error after the capture
      When I run riddim with:
        """
        peek worker 3
        """
      Then standard error is empty

  Rule: The visible viewport is captured exactly

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a Herdr executable that answers a pane read with 250 lines

    Scenario: Read the visible source without a line count
      When I run riddim with:
        """
        peek worker --visible
        """
      Then Herdr is invoked with "--session riddim pane read w9:p1 --source visible"

    Scenario: Pass the visible capture through whole
      When I run riddim with:
        """
        peek worker --visible
        """
      Then standard output is the whole pane read

    Scenario: Preserve Herdr's failure for the visible read
      Given Herdr fails the pane read with status 17 and error "herdr: pane not found"
      When I run riddim with:
        """
        peek worker --visible
        """
      Then the command exits with status 17

  Rule: A line count and --visible are mutually exclusive

    Background:
      Given a fake Herdr executable

    Scenario: Reject a line count after the flag
      When I run riddim with:
        """
        peek worker --visible 5
        """
      Then the command exits with status 2

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        peek worker --visible 5
        """
      Then standard error is "Usage: riddim peek <name> [lines|--visible]"

    Scenario: Read no pane when the flag is misplaced
      When I run riddim with:
        """
        peek --visible worker
        """
      Then the command exits with status 2

  Rule: Forty lines are read by default

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a Herdr executable that answers a pane read with 250 lines

    Scenario: Fetch the generous minimum without a line count
      When I run riddim with:
        """
        peek worker
        """
      Then Herdr is invoked with "--session riddim pane read w9:p1 --source recent --lines 200"

    Scenario: Print forty lines by default
      When I run riddim with:
        """
        peek worker
        """
      Then standard output is the final 40 lines of the pane read

  Rule: The recorded session overrides the ambient session

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And a Herdr executable that answers a pane read with 250 lines
      And the Herdr session is "ambient"

    Scenario: Target the recorded session, not the ambient one
      When I run riddim with:
        """
        peek worker 5
        """
      Then Herdr is invoked with "--session riddim pane read w9:p1 --source recent --lines 200"

  Rule: A missing record is refused before Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        peek ghost 5
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's own refusal status
      When I run riddim with:
        """
        peek ghost 5
        """
      Then the command exits with status 1

    Scenario: Name the missing record
      When I run riddim with:
        """
        peek ghost 5
        """
      Then the missing record refusal is explained for "ghost"

  Rule: A malformed record is refused before Herdr

    Background:
      Given a fake Herdr executable
      And an existing endpoint record for "worker" that is not a record

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        peek worker 5
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's own refusal status
      When I run riddim with:
        """
        peek worker 5
        """
      Then the command exits with status 1

    Scenario: Name the unreadable record
      When I run riddim with:
        """
        peek worker 5
        """
      Then the unreadable record refusal is explained for "worker"

  Rule: A symlinked record is refused before Herdr

    Background:
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere

    Scenario: Fail closed without following the link
      When I run riddim with:
        """
        peek worker 5
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's own refusal status
      When I run riddim with:
        """
        peek worker 5
        """
      Then the command exits with status 1

    Scenario: Name the symlinked record
      When I run riddim with:
        """
        peek worker 5
        """
      Then the symlinked record refusal is explained for "worker"

  Rule: Malformed Herdr endpoint ids are refused before Herdr

    Background:
      Given a fake Herdr executable
      And an endpoint record for "worker" with a malformed Herdr session

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        peek worker 5
        """
      Then Herdr receives no invocation

  Rule: A record inconsistent with the requested name is refused before Herdr

    Background:
      Given a fake Herdr executable
      And an endpoint record for "worker" whose window names another pane

    Scenario: Fail closed without invoking Herdr
      When I run riddim with:
        """
        peek worker 5
        """
      Then Herdr receives no invocation

    Scenario: Exit with Riddim's own refusal status
      When I run riddim with:
        """
        peek worker 5
        """
      Then the command exits with status 1

    Scenario: Name the inconsistent window
      When I run riddim with:
        """
        peek worker 5
        """
      Then the inconsistent window refusal is explained for "worker"

  Rule: Herdr's failure is preserved

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr fails the pane read with status 17 and error "herdr: pane not found"

    Scenario: Propagate Herdr's failure status
      When I run riddim with:
        """
        peek worker 5
        """
      Then the command exits with status 17

    Scenario: Preserve Herdr's error
      When I run riddim with:
        """
        peek worker 5
        """
      Then standard error is "herdr: pane not found"

    Scenario: Preserve Herdr's partial output untrimmed
      When I run riddim with:
        """
        peek worker 5
        """
      Then standard output is "partial tail"

  Rule: The command accepts exactly a name and an optional line count

    Scenario: Reject a missing name
      When I run riddim with:
        """
        peek
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a name
      When I run riddim with:
        """
        peek
        """
      Then standard error is "Usage: riddim peek <name> [lines|--visible]"

    Scenario: Reject extra arguments
      When I run riddim with:
        """
        peek worker 5 extra
        """
      Then the command exits with status 2

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        peek worker 5 extra
        """
      Then standard error is "Usage: riddim peek <name> [lines|--visible]"

  Rule: The name must name a started agent

    Scenario: Reject a name outside the agent-name shape
      When I run riddim with:
        """
        peek Worker
        """
      Then the command exits with status 2

    Scenario: Explain the agent-name shape
      When I run riddim with:
        """
        peek Worker
        """
      Then standard error is "riddim: name must match [a-z][a-z0-9_-]{0,31}"

  Rule: The line count must be positive

    Scenario: Reject a non-positive line count
      When I run riddim with:
        """
        peek worker 0
        """
      Then the command exits with status 2

    Scenario: Explain that the line count must be positive
      When I run riddim with:
        """
        peek worker 0
        """
      Then standard error is "riddim: lines must be a positive integer"