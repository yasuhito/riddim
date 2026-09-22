# frozen_string_literal: true

module Riddim
  # The structural composer scan of Riddim::Herdr: the bottom-most closed pi
  # separator pair and the competing-shape guards that keep the shared
  # classifier's cursorless refusal rules intact.
  module Herdr
    # The agent prompt glyphs Firstmate declares once for the whole fleet: a
    # bare row leading with one is a composer candidate that outranks a pi
    # pair below it. Shell glyphs never prove a composer.
    AGENT_GLYPHS = %w[❯ › ⟩ →].freeze

    # The bare shell glyphs: a row leading with one is a dead-shell prompt or
    # shell output, and the owner refuses on one below the selected shape.
    SHELL_GLYPHS = %w[> $ % #].freeze

    # The box corner rows Firstmate's scan pairs into bordered boxes. A row
    # starting with any of them is either a box edge or an unclosed box, both
    # of which outrank or refuse a pi pair below them.
    BOX_CORNERS = %w[╭ ╮ ╰ ╯ ┌ ┐ └ ┘ ╔ ╗ ╚ ╝ ┏ ┓ ┗ ┛].freeze

    module_function

    # The bottom-most closed separator pair, guarded the way the shared
    # cursorless selection refuses: another shape below the pair's close (a
    # box border, a bare agent glyph, a left bar, a shell glyph) would win
    # selection in the owner, so Riddim refuses rather than misreading a pair
    # it would never have selected.
    def bottom_most_pi_pair(screen)
      scan = scan_composer_rows(plain_rows(screen))
      separators = scan.fetch(:separators)
      return nil if separators.length < 2

      close = separators[-1]
      return nil if scan.fetch(:last_shell_row) > close || scan.fetch(:last_competing_row) > close

      { open: separators[-2], close: close, valid: (close - separators[-2] - 1) <= PI_MAX_LINES }
    end

    def scan_composer_rows(rows)
      scan = { separators: [], last_shell_row: -1, last_competing_row: -1 }
      rows.each_with_index do |row, index|
        scan[:separators] << index if pi_separator_row?(row)
        scan[:last_shell_row] = index if leading_glyph?(row, SHELL_GLYPHS)
        scan[:last_competing_row] = index if competing_shape_row?(row)
      end
      scan
    end

    # The plain (ANSI-stripped, normalized, trimmed) rows the structural scan
    # runs on, exactly like the shared classifier's plain screen pass.
    def plain_rows(screen)
      screen.split("\n", -1).map { |row| normalize_trim(strip_ansi(row)) }
    end

    def screen_rows(screen)
      screen.split("\n", -1)
    end

    # A solid pi separator: nothing but `─`, at least 8 columns wide, exactly
    # like Firstmate's byte-exact substring test.
    def pi_separator_row?(trimmed)
      !trimmed.empty? && trimmed.delete('─').empty? && trimmed.include?('────────')
    end

    # A box border, a bare agent-glyph row, or a left-bar row below the pair's
    # close is a competing composer candidate: the shared classifier would
    # select it, so Riddim refuses instead of classifying a pair it would
    # never have selected.
    def competing_shape_row?(trimmed)
      return true if leading_glyph?(trimmed, AGENT_GLYPHS)

      first = trimmed[0]
      BOX_CORNERS.include?(first) || first == '┃'
    end

    def leading_glyph?(trimmed, glyphs)
      glyphs.include?(trimmed[0])
    end
  end
end
