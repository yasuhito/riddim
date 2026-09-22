# frozen_string_literal: true

module Riddim
  # The pane-tail read surface of Riddim::Herdr, kept apart from the
  # agent-and-workspace surface in herdr.rb: Firstmate's Herdr pane capture,
  # reduced to what Riddim owns. One session-targeted read of one exact
  # pane's recent output, trimmed locally to the requested tail. It is a
  # plain pane read - never `agent read`, and never an unwrapped source - and
  # Herdr's own failure is preserved for the caller.
  module Herdr
    # The smallest recent pane read Herdr can be trusted to answer: a bound
    # below the pane's viewport height makes `pane read --lines N` return
    # nothing at all (the pane-read bound quirk Firstmate documents), so the
    # capture always fetches at least this many recent lines and trims
    # locally to the requested tail.
    PANE_TAIL_MIN_FETCH = 200

    module_function

    # Firstmate's Herdr pane capture, reduced to what Riddim owns: one
    # session-targeted read of one exact pane's recent output, trimmed locally
    # to the requested tail. The fetch asks for the requested count, never
    # below Firstmate's 200-line minimum, because Herdr's `pane read --lines
    # N` returns nothing at all when N is smaller than the pane's viewport
    # height; the requested tail is cut from the generous capture afterwards.
    def pane_tail(session:, pane_id:, lines:)
      stdout, stderr, status = capture(
        'pane', 'read', pane_id, '--source', 'recent', '--lines', fetch_lines(lines).to_s,
        session: session
      )
      raise CommandFailed.new(stdout, stderr, status.exitstatus) unless status.success?

      tail(stdout, lines)
    end

    # The generous read bound for one tail: the requested count, never below
    # Firstmate's 200-line minimum.
    def fetch_lines(lines)
      [lines, PANE_TAIL_MIN_FETCH].max
    end

    # The final <count> lines of one capture, exactly like `tail -n <count>`:
    # every line beyond the caller's bound is dropped here, in this process,
    # and a capture shorter than the bound is passed through whole.
    def tail(output, count)
      output.lines.last(count).join
    end
  end
end
