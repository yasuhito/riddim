# frozen_string_literal: true

module Riddim
  # Validates Herdr compatibility before creating an endpoint.
  module Herdr
    class IncompatibleClient < StandardError; end

    module_function

    # Firstmate supports protocol 14, but Riddim uses disposable workspaces
    # and requires the 0.8.0 focus-safe emptying-close fix as well. Status is
    # available before a named server starts.
    def verify_client!
      stdout, stderr, status = capture('status', '--json')
      raise CommandFailed.new(stdout, stderr, status) unless status.success?

      validate_client_status(JSON.parse(stdout))
    rescue JSON::ParserError
      raise IncompatibleClient, 'incompatible Herdr client/server: malformed status JSON'
    end

    def validate_client_status(document)
      client = document['client'] if document.is_a?(Hash)
      protocol = client['protocol'] if client.is_a?(Hash)
      unless protocol.is_a?(Integer) && protocol >= 14 && supported_release?(client['version'])
        raise IncompatibleClient, 'incompatible Herdr client: expected protocol >= 14 and version >= 0.8.0'
      end

      validate_running_server(document['server'])
    end

    def validate_running_server(server)
      unless server.is_a?(Hash) && [true, false].include?(server['running'])
        raise IncompatibleClient, 'incompatible Herdr server: running state is unreadable'
      end
      return unless server['running']
      return if supported_release?(server['version'])

      raise IncompatibleClient, 'incompatible Herdr server: expected running version >= 0.8.0'
    end

    def supported_release?(value)
      return false unless value.is_a?(String) && value.match?(/\A\d+\.\d+\.\d+(?:[-+].*)?\z/)

      (value.split(/[.\-+]/).first(3).map(&:to_i) <=> [0, 8, 0]) >= 0
    end
  end
end
