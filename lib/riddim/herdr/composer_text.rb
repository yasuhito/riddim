# frozen_string_literal: true

module Riddim
  # The composer text primitives of Riddim::Herdr: ANSI stripping, Unicode
  # whitespace normalization, and Firstmate's ANSI-aware ghost extractor, all
  # byte-faithful ports of the shared composer owner's helpers.
  module Herdr
    # Dark-truecolor foregrounds below this perceived luma read as ghost text
    # (Firstmate's FM_COMPOSER_GHOST_LUMA_MAX default).
    GHOST_LUMA_MAX = 128

    # The SGR colour codes whose payload the ghost stripper must skip: a
    # truecolor foreground (also luma-tested), a background, an underline
    # colour.
    COLOR_PAYLOAD_CODES = %w[38 48 58].freeze

    # The SGR codes that set the dim/faint de-emphasis, and the value each sets.
    DIM_CODES = { '2' => true, '0' => false, '22' => false }.freeze

    # The SGR codes that end a dark-truecolor run: a reset, a default
    # foreground, and every base foreground colour.
    DARK_RESET_CODES = %w[0 39].freeze + %w[30 31 32 33 34 35 36 37] + %w[90 91 92 93 94 95 96 97]
    DARK_RESET_CODES.freeze

    # The side-border pairs stripped from captured content rows.
    SIDE_BORDERS = %w[│ ┃ ║ |].freeze

    # The Unicode White_Space code points outside ASCII that Firstmate's
    # normalizer maps onto plain spaces, declared as code points so each stays
    # reviewable in source. U+200B is deliberately absent: Unicode gives it
    # White_Space=No.
    UNICODE_SPACES = [
      0x85, 0xA0, 0x1680, *0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000
    ].map { |codepoint| codepoint.chr(Encoding::UTF_8) }.freeze

    private_constant :DARK_RESET_CODES, :UNICODE_SPACES

    module_function

    # Firstmate's _fm_composer_row_content: the real content of one captured
    # row - ghost-stripped when the capture preserves styling, ANSI-stripped
    # otherwise - then trimmed and stripped of matching side borders.
    def composer_row_content(raw, styled)
      stripped = normalize_trim(styled ? strip_ghost(raw) : strip_ansi(raw))
      stripped = strip_side_borders(stripped)

      normalize_trim(stripped)
    end

    def strip_side_borders(stripped)
      bordered = stripped.length >= 2 && SIDE_BORDERS.include?(stripped[0]) && stripped[-1] == stripped[0]
      return stripped unless bordered

      stripped[1..-2]
    end

    def normalize_trim(text)
      normalized = UNICODE_SPACES.reduce(text) { |acc, space| acc.gsub(space, ' ') }

      normalized.strip
    end

    def strip_ansi(line)
      line.gsub(/\e\[[0-9;:?]*[A-Za-z]/, '')
    end

    # Firstmate's fm_composer_strip_ghost: the ONE ANSI-aware extractor of
    # real typed content from a styled row, dropping dim/faint runs (SGR 2)
    # and dark-truecolor foreground runs (SGR 38;2 below the luma floor). A
    # 256-colour foreground is deliberately never luminance-tested:
    # palette-dependence would risk stripping real text, and under-stripping
    # only ever defers.
    def strip_ghost(line)
      out = +''
      state = { dim: false, dark: false }
      ghost_scan(line, out, state)
      out
    end

    def ghost_scan(line, out, state)
      index = 0
      while index < line.length
        char = line[index]
        if char == "\e"
          index = advance_ghost_escape(line, index, state)
        else
          out << char unless state[:dim] || state[:dark]
          index += 1
        end
      end
    end

    # Consumes one escape sequence from <index> and returns the next index. A
    # CSI sequence is consumed whole; a lone or unterminated ESC drops the ESC
    # byte only, exactly like the awk the owner runs.
    def advance_ghost_escape(line, index, state)
      return index + 1 unless line[index + 1] == '['

      final = csi_final_index(line, index + 2)
      return index + 1 if final >= line.length

      apply_sgr_params(line[(index + 2)...final], state) if line[final] == 'm'

      final + 1
    end

    def csi_final_index(line, start)
      cursor = start
      cursor += 1 while cursor < line.length && !line[cursor].match?(/[@-~]/)
      cursor
    end

    # One SGR sequence, processed left to right: a 38 foreground starts (or
    # clears) the dark-truecolour run, 48/58 payloads are skipped without
    # touching de-emphasis, and the remaining codes set or clear dim/faint.
    def apply_sgr_params(params, state)
      codes = params.split(';')
      index = 0
      index = advance_sgr_code(codes, index, state) + 1 while index < codes.length
    end

    def advance_sgr_code(codes, index, state)
      code = sgr_code(codes[index])
      if code == '38'
        state[:dark] = dark_truecolor?(codes, index)
        return skip_color_payload(codes, index)
      end
      return skip_color_payload(codes, index) if COLOR_PAYLOAD_CODES.include?(code)

      state[:dim] = DIM_CODES.fetch(code) if DIM_CODES.key?(code)
      state[:dark] = false if DARK_RESET_CODES.include?(code) || base_foreground_code?(code)
      index
    end
  end
end
