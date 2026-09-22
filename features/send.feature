Feature: Send a message to an agent

  Rule: A valid message is forwarded to Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Forward the message to Herdr
      When I run riddim with:
        """
        send pi Fix the tests
        """
      Then Herdr receives "--session default agent prompt pi Fix the tests"

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

  Rule: A later --wait stays message text

    Background:
      Given a fake Herdr executable

    Scenario: Keep a later wait flag in an ordinary message
      When I run riddim with:
        """
        send pi try --wait
        """
      Then Herdr receives "--session default agent prompt pi try --wait"

  Rule: A nonempty HERDR_SESSION names the session

    Background:
      Given a fake Herdr executable
      And the Herdr session is "lab"

    Scenario: Forward the message through the named session
      When I run riddim with:
        """
        send pi Fix the tests
        """
      Then Herdr receives "--session lab agent prompt pi Fix the tests"

  Rule: send --wait is rejected without invoking Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Reject a send --wait invocation
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then the command exits with status 2

    Scenario: Explain that send --wait is unsupported
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then standard error is "riddim: send --wait is unsupported; use riddim send <target> <message...>"

    Scenario: Reject a bare send --wait the same way
      When I run riddim with:
        """
        send --wait
        """
      Then standard error is "riddim: send --wait is unsupported; use riddim send <target> <message...>"

    Scenario: Invoke no Herdr command for a rejected send --wait
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then Herdr receives no invocation

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
