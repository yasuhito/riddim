Feature: Read recent agent output

  Rule: Output is read from Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Read the requested number of lines
      When I run riddim with:
        """
        peek pi 5
        """
      Then Herdr receives "--session default agent read pi --source recent-unwrapped --lines 5"

    Scenario: Exit successfully after reading output
      When I run riddim with:
        """
        peek pi 5
        """
      Then the command succeeds

    Scenario: Write no error after reading output
      When I run riddim with:
        """
        peek pi 5
        """
      Then standard error is empty

    Scenario: Read forty lines by default
      When I run riddim with:
        """
        peek pi
        """
      Then Herdr receives "--session default agent read pi --source recent-unwrapped --lines 40"

    Scenario: Exit successfully with the default line count
      When I run riddim with:
        """
        peek pi
        """
      Then the command succeeds

    Scenario: Write no error with the default line count
      When I run riddim with:
        """
        peek pi
        """
      Then standard error is empty

  Rule: A nonempty HERDR_SESSION names the session

    Background:
      Given a fake Herdr executable
      And the Herdr session is "lab"

    Scenario: Read through the named session
      When I run riddim with:
        """
        peek pi 5
        """
      Then Herdr receives "--session lab agent read pi --source recent-unwrapped --lines 5"

  Rule: The line count must be positive

    Scenario: Reject a non-positive line count
      When I run riddim with:
        """
        peek pi 0
        """
      Then the command exits with status 2

    Scenario: Write no output for a non-positive line count
      When I run riddim with:
        """
        peek pi 0
        """
      Then standard output is empty

    Scenario: Explain that the line count must be positive
      When I run riddim with:
        """
        peek pi 0
        """
      Then standard error is "riddim: lines must be a positive integer"

  Rule: The command accepts only a target and an optional line count

    Scenario: Reject a missing target
      When I run riddim with:
        """
        peek
        """
      Then the command exits with status 2

    Scenario: Write no output when the target is missing
      When I run riddim with:
        """
        peek
        """
      Then standard output is empty

    Scenario: Explain how to provide a target
      When I run riddim with:
        """
        peek
        """
      Then standard error is "Usage: riddim peek <target> [lines]"

    Scenario: Reject extra arguments
      When I run riddim with:
        """
        peek pi 5 extra
        """
      Then the command exits with status 2

    Scenario: Write no output for extra arguments
      When I run riddim with:
        """
        peek pi 5 extra
        """
      Then standard output is empty

    Scenario: Explain the accepted arguments
      When I run riddim with:
        """
        peek pi 5 extra
        """
      Then standard error is "Usage: riddim peek <target> [lines]"
