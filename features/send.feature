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

  Rule: Wait mode delegates the prompt and the wait to Herdr

    Background:
      Given a fake Herdr executable

    Scenario: Delegate the prompt with the wait flag
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then Herdr receives "agent prompt pi Fix the tests --wait"

    Scenario: Exit successfully when Herdr reaches a terminal state
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then the command succeeds

    Scenario: Write no error after waiting
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then standard error is empty

  Rule: Only the first argument after send enables wait mode

    Background:
      Given a fake Herdr executable

    Scenario: Keep a later wait flag in an ordinary message
      When I run riddim with:
        """
        send pi try --wait
        """
      Then Herdr receives "agent prompt pi try --wait"

    Scenario: Keep a later wait flag in a wait-mode message
      When I run riddim with:
        """
        send --wait pi try --wait again
        """
      Then Herdr receives "agent prompt pi try --wait again --wait"

  Rule: A failed wait is preserved

    Scenario: Propagate Herdr's failure status
      Given Herdr fails to prompt with status 3 and error "herdr: agent_prompt_stalled"
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then the command exits with status 3

    Scenario: Propagate Herdr's failure error
      Given Herdr fails to prompt with status 3 and error "herdr: agent_prompt_stalled"
      When I run riddim with:
        """
        send --wait pi Fix the tests
        """
      Then standard error is "herdr: agent_prompt_stalled"

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

  Rule: Wait mode requires a target and a message

    Scenario: Reject a missing target
      When I run riddim with:
        """
        send --wait
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a target while waiting
      When I run riddim with:
        """
        send --wait
        """
      Then standard error is "Usage: riddim send --wait <target> <message...>"

    Scenario: Reject a missing message
      When I run riddim with:
        """
        send --wait pi
        """
      Then the command exits with status 2

    Scenario: Explain how to provide a message while waiting
      When I run riddim with:
        """
        send --wait pi
        """
      Then standard error is "Usage: riddim send --wait <target> <message...>"

    Scenario: Reject a blank wait-mode message
      When I run riddim with:
        """
        send --wait pi "   "
        """
      Then the command exits with status 2

    Scenario: Explain that a blank wait-mode message is invalid
      When I run riddim with:
        """
        send --wait pi "   "
        """
      Then standard error is "riddim: message must not be blank"
