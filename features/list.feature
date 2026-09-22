Feature: List recorded agent endpoints

  This is a read-only subset of Firstmate's fleet snapshot. Records, not Herdr
  labels, select agents. The output reports recorded ownership, never process
  liveness or agent activity; an invalid record is not silently omitted.

  Rule: Show validated ownership records in name order

    Background:
      Given a fake Herdr executable
      And a published endpoint record for "zeta" in session "secondary" naming pane "w8:p1"
      And a published endpoint record for "alpha" in session "riddim" naming pane "w9:p1"

    Scenario: Print each name and its recorded endpoint
      When I run riddim with:
        """
        list
        """
      Then standard output is the sorted endpoint list

    Scenario: Do not ask Herdr to discover agents
      When I run riddim with:
        """
        list
        """
      Then Herdr receives no invocation

    Scenario: Return success for valid records
      When I run riddim with:
        """
        list
        """
      Then the command succeeds

  Rule: No records is an empty, successful list

    Scenario: An absent state directory prints nothing
      When I run riddim with:
        """
        list
        """
      Then standard output is empty

    Scenario: An empty state directory returns success
      Given an empty state directory
      When I run riddim with:
        """
        list
        """
      Then the command succeeds

    Scenario: An unpublished staging file is not ownership
      Given a staged record that was never published
      When I run riddim with:
        """
        list
        """
      Then standard output is empty

  Rule: Fail closed instead of hiding malformed ownership

    Background:
      Given a fake Herdr executable
      And a published endpoint record for "alpha" in session "riddim" naming pane "w9:p1"
      And an existing endpoint record for "zeta" that is not a record

    Scenario: Do not print a misleading partial list
      When I run riddim with:
        """
        list
        """
      Then standard output is empty

    Scenario: Explain the invalid record
      When I run riddim with:
        """
        list
        """
      Then standard error includes "the endpoint record for zeta"

    Scenario: Fail without probing Herdr
      When I run riddim with:
        """
        list
        """
      Then Herdr receives no invocation

  Rule: Refuse unsafe record paths

    Background:
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere

    Scenario: Do not follow symlinks
      When I run riddim with:
        """
        list
        """
      Then standard error includes "symbolic link"

    Scenario: Do not silently skip unsafe records
      When I run riddim with:
        """
        list
        """
      Then the command exits with status 1

  Rule: Refuse malformed inventory paths

    Scenario: Do not follow a symlinked state directory
      Given a state directory symlink
      When I run riddim with:
        """
        list
        """
      Then standard error includes "state directory is not a real directory"

    Scenario: Do not silently omit a non-agent meta filename
      Given a malformed record filename
      When I run riddim with:
        """
        list
        """
      Then the command exits with status 1

    Scenario: Refuse an invalid UTF-8 filename without a backtrace
      Given a record filename containing invalid UTF-8
      When I run riddim with:
        """
        list
        """
      Then standard error includes "invalid endpoint record filename"

  Rule: List has no positional selector

    Scenario: Reject unexpected arguments
      When I run riddim with:
        """
        list worker
        """
      Then the command exits with status 2
