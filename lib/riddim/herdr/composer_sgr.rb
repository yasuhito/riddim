# frozen_string_literal: true

module Riddim
  # The SGR state machine of Riddim::Herdr's ghost stripper: how de-emphasis
  # runs start and end, how colour payloads are skipped, and how a dark
  # truecolor foreground is judged.
  module Herdr
    module_function

    def base_foreground_code?(code)
      numeric = code.to_i

      numeric.between?(30, 37) || numeric.between?(90, 97)
    end

    def sgr_code(value)
      code = value.to_s.split(':').first
      code.nil? || code.empty? ? '0' : code
    end

    def dark_truecolor?(codes, index)
      spec = codes[index]
      return colon_truecolor_dark?(spec.split(':')) if spec.include?(':')

      semicolon_truecolor_dark?(codes, index)
    end

    def colon_truecolor_dark?(fields)
      return false if fields[1] != '2' || fields.length < 5

      luma_below_threshold?(fields.last(3))
    end

    def semicolon_truecolor_dark?(codes, index)
      return false if index + 4 > codes.length - 1 || codes[index + 1] != '2'

      luma_below_threshold?(codes[index + 2, 3])
    end

    def skip_color_payload(codes, index)
      return index if codes[index].include?(':')
      return index if index >= codes.length - 1

      mode = codes[index + 1]
      return index + 1 if mode.include?(':')

      case sgr_code(mode)
      when '5' then index + 2
      when '2' then index + 4
      else index + 1
      end
    end

    def luma_below_threshold?(rgb)
      red, green, blue = rgb.map(&:to_f)
      weighted = (299 * red) + (587 * green) + (114 * blue)

      weighted / 1000 < GHOST_LUMA_MAX
    end
  end
end
