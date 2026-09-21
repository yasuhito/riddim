Feature: Send a message to an agent

  Rule: A valid message is forwarded to Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Forward the message to Herdr
      When I run riddim with:
        """
        send pi Fix the tests
        """
      Then Herdr receives "agent prompt pi Fix the tests"

    Scenario: Exit successfully
      When I run riddim with:
        """
        send pi Fix the tests
        """
      Then the command succeeds

    Scenario: Write no error
      When I run riddim with:
        """
        send pi Fix the tests
        """
      Then standard error is empty

  Rule: A target and a message are required

    Scenario: Reject a missing target
      When I run riddim with:
        """
        send
        """
      Then the command exits with status 2

    Scenario: Write no output when the target is missing
      When I run riddim with:
        """
        send
        """
      Then standard output is empty

    Scenario: Explain how to provide a target
      When I run riddim with:
        """
        send
        """
      Then standard error is "Usage: riddim send <target> <message...>"

    Scenario: Reject a missing message
      When I run riddim with:
        """
        send pi
        """
      Then the command exits with status 2

    Scenario: Write no output when the message is missing
      When I run riddim with:
        """
        send pi
        """
      Then standard output is empty

    Scenario: Explain how to provide a message
      When I run riddim with:
        """
        send pi
        """
      Then standard error is "Usage: riddim send <target> <message...>"

  Rule: A blank message is invalid

    Scenario: Reject a blank message
      When I run riddim with:
        """
        send pi "   "
        """
      Then the command exits with status 2

    Scenario: Write no output for a blank message
      When I run riddim with:
        """
        send pi "   "
        """
      Then standard output is empty

    Scenario: Explain that a blank message is invalid
      When I run riddim with:
        """
        send pi "   "
        """
      Then standard error is "riddim: message must not be blank"
