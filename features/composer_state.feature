Feature: Classify a recorded pane's composer

  This is a Pi-only subset of Firstmate's shared composer classifier: the pi
  separated-pair shape, proven by Herdr's native identity probe. The verdict
  is empty | pending | unknown; only an exact `empty` may ever authorize
  typing, and every unprovable screen refuses.

  Rule: An idle pi composer is proven empty

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves composer screens
      And the identity probe reports pi as idle

    Scenario: A blank pair between separators reads empty
      Given the styled composer capture is:
        """
        ────────────

        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "empty"

    Scenario: A dim placeholder inside the pair is ghost text, not input
      Given the styled composer capture is dim placeholder inside a pair
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "empty"

    Scenario: Adjacent separators bound an empty region
      Given the styled composer capture is:
        """
        ────────────
        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "empty"

  Rule: Proven input reads pending

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves composer screens
      And the identity probe reports pi as idle

    Scenario: Typed text inside the pair reads pending
      Given the styled composer capture is:
        """
        ────────────
        finish the failing test
        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "pending"

    Scenario: Bright input beside a dim placeholder reads pending
      Given the styled composer capture is a dim placeholder beside bright input
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "pending"

  Rule: Every unprovable screen refuses

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves composer screens
      And the identity probe reports pi as idle

    Scenario: A screen without a separator pair stays unknown
      Given the styled composer capture is:
        """
        shell prompt and output
        more output
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A pair wider than eight inner rows is a transcript gap
      Given the styled composer capture holds nine inner rows
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A bare agent glyph below the pair outranks it
      Given the styled composer capture ends below the pair:
        """
        ❯ stray row
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A shell glyph below the pair refuses
      Given the styled composer capture ends below the pair:
        """
        $ prompt
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A box border below the pair outranks it
      Given the styled composer capture ends below the pair:
        """
        ╭──╮
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A working pi never proves an empty composer
      Given the identity probe reports pi as working
      And the styled composer capture is:
        """
        ────────────

        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A blocked pi is parked on its own prompt
      Given the identity probe reports pi as blocked
      And the styled composer capture is:
        """
        ────────────

        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A foreign agent never proves an empty composer
      Given the identity probe reports a foreign agent
      And the styled composer capture is:
        """
        ────────────

        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: A failed identity probe refuses
      Given the identity probe finds no agent
      And the styled composer capture is:
        """
        ────────────

        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

    Scenario: Malformed identity JSON refuses
      Given the identity probe replies with malformed JSON
      And the styled composer capture is:
        """
        ────────────

        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

  Rule: The styled capture degrades before giving up

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves composer screens
      And the identity probe reports pi as idle
      And Herdr fails the styled composer read only

    Scenario: The plain fallback still proves typed input
      Given the plain composer capture is:
        """
        ────────────
        typed draft
        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then Herdr reads the plain fallback capture first

    Scenario: An unreadable placeholder degrades to pending, never empty
      Given the plain composer capture is:
        """
        ────────────
        Type a message
        ────────────
        """
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "pending"

    Scenario: Every failed read stays unknown
      Given Herdr fails every composer read
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

  Rule: Only the exact recorded pane and session are read

    Background:
      Given a published endpoint record for "worker" in session "riddim" naming pane "w9:p1"
      And Herdr serves composer screens
      And the identity probe reports pi as idle
      And the styled composer capture is:
        """
        ────────────

        ────────────
        """

    Scenario: Read only the exact recorded styled capture
      When I run riddim with:
        """
        composer-state worker
        """
      Then Herdr reads the composer capture and the identity probe

    Scenario: The ambient session is never trusted
      Given the Herdr session is "ambient"
      When I run riddim with:
        """
        composer-state worker
        """
      Then every Herdr call targets session "riddim"

    Scenario: A changed owner discards the composer verdict
      Given ownership is rebound while Herdr reads the composer
      When I run riddim with:
        """
        composer-state worker
        """
      Then standard output is "unknown"

  Rule: Only valid ownership may be inspected

    Scenario: Reject a bare pane ID
      When I run riddim with:
        """
        composer-state w9:p1
        """
      Then the command exits with status 2

    Scenario: Require a name
      When I run riddim with:
        """
        composer-state
        """
      Then the command exits with status 2

    Scenario: Refuse a symlinked record before consulting Herdr
      Given a fake Herdr executable
      And a symlinked endpoint record for "worker" that points elsewhere
      When I run riddim with:
        """
        composer-state worker
        """
      Then Herdr receives no invocation