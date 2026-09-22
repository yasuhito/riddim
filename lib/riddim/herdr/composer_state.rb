# frozen_string_literal: true

module Riddim
  # The composer adapter surface of Riddim::Herdr: Firstmate's Herdr composer
  # capture and its pi separated-shape verdict, reduced to what Riddim owns.
  # The verdict is one of empty | pending | unknown, and it gates nothing by
  # itself: only an exact `empty` may ever authorize typing into a pane.
  module Herdr
    # The adapter's bounded composer capture: the last <n> lines of a generous
    # recent read (Firstmate's FM_COMPOSER_CAPTURE_LINES default).
    COMPOSER_CAPTURE_LINES = 20

    # A separated pair whose inner region exceeds this many rows is a
    # transcript gap between two far-apart rules, not a composer (Firstmate's
    # FM_COMPOSER_PI_MAX_LINES default).
    PI_MAX_LINES = 8

    module_function

    # Firstmate's fm_backend_herdr_composer_state: one styled (ANSI) capture
    # preferred, a plain capture as the styled=0 fallback, and a lazy identity
    # probe only when the classifier's verdict depends on it.
    def composer_state(pane, session:)
      screen, styled = composer_capture(pane, session: session)
      return :unknown unless screen

      verdict = pi_composer_verdict(screen, styled: styled, identity: nil)
      return composer_identity_verdict(screen, styled, pane, session: session) if verdict == :need_identity

      verdict
    end

    def composer_identity_verdict(screen, styled, pane, session:)
      identity = composer_identity(pane, session: session) || 'probe-absent'

      pi_composer_verdict(screen, styled: styled, identity: identity)
    end

    def composer_capture(pane, session:)
      stdout, _stderr, status = capture(
        'pane', 'read', pane, '--source', 'recent', '--lines', composer_fetch_lines.to_s,
        '--format', 'ansi', session: session
      )
      return [tail(stdout, COMPOSER_CAPTURE_LINES), true] if status.success?

      stdout, _stderr, status = capture(
        'pane', 'read', pane, '--source', 'recent', '--lines', composer_fetch_lines.to_s, session: session
      )
      return [tail(stdout, COMPOSER_CAPTURE_LINES), false] if status.success?

      nil
    end

    def composer_fetch_lines
      fetch_lines(COMPOSER_CAPTURE_LINES)
    end

    # Firstmate's fm_backend_herdr_agent_identity_raw: the native identity
    # probe as "<agent>\t<agent_status>", or nil when the probe found nothing
    # readable (the adapter's `probe-absent`).
    def composer_identity(pane, session:)
      stdout, _stderr, status = capture('agent', 'get', pane, session: session)
      return nil unless status.success?

      document = JSON.parse(stdout)
      result = document['result'] if document.is_a?(Hash)
      agent = result['agent'] if result.is_a?(Hash)
      return nil unless agent.is_a?(Hash)

      "#{agent['agent']}\t#{agent['agent_status']}"
    rescue JSON::ParserError
      nil
    end

    # The pi separated-shape verdict: identity + structure conjunction. Any
    # non-empty inner row is proven input; only an idle/done live pi proves an
    # empty composer, because a working pi is mid-turn and a blocked pi is
    # parked on its own prompt, where composed keys would answer the prompt
    # instead of composing.
    def pi_composer_verdict(screen, styled:, identity:)
      pair = bottom_most_pi_pair(screen)
      return :unknown unless pair
      return :need_identity if identity.nil?

      pi_identity_verdict(screen, styled: styled, pair: pair, identity: identity)
    end

    def pi_identity_verdict(screen, styled:, pair:, identity:)
      return :unknown if identity == 'probe-absent'

      agent, agent_status = identity.split("\t")
      return :unknown unless agent == 'pi' && pair.fetch(:valid)
      return :pending if pair_inner_pending?(screen, styled: styled, pair: pair)

      %w[idle done].include?(agent_status) ? :empty : :unknown
    end

    def pair_inner_pending?(screen, styled:, pair:)
      rows = screen_rows(screen)
      ((pair.fetch(:open) + 1)...pair.fetch(:close)).any? do |index|
        !composer_row_content(rows.fetch(index, ''), styled).empty?
      end
    end
  end
end
