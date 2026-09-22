# frozen_string_literal: true

module Riddim
  # Read-only state of the Herdr server behind one recorded session.
  module Herdr
    module_function

    # Read-only subset of Firstmate's fm_backend_herdr_server_running_state:
    # the recorded session's `status --json` is the only evidence. A
    # positively stopped server means "unreachable right now": Herdr
    # preserves pane, tab, and workspace ids across a server restart, so
    # stopped never proves an endpoint was destroyed and never licenses
    # recovery on its own. Every ambiguous read stays unknown.
    def server_running_state(session:)
      stdout, _stderr, status = capture('status', '--json', session: session)
      return :unknown unless status.success?

      server = parsed_server(stdout)
      case server['running']
      when true then :running
      when false then :stopped
      else :unknown
      end
    rescue JSON::ParserError
      :unknown
    end

    def parsed_server(stdout)
      document = JSON.parse(stdout)
      server = document['server'] if document.is_a?(Hash)
      server.is_a?(Hash) ? server : {}
    end
  end
end
