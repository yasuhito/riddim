# frozen_string_literal: true

module Riddim
  # Read-only classification of the exact pane recorded for a Pi agent.
  module Herdr
    module_function

    # Read-only, Pi-only subset of Firstmate's recovery-grade Herdr verdicts.
    # :missing covers an absent pane OR a stopped server: it does not prove an
    # endpoint was destroyed and never licenses a lifecycle mutation by itself.
    def agent_state(pane, session:)
      stdout, stderr, _status = capture('pane', 'get', pane, session: session)
      case pane_presence(pane, stdout, stderr)
      when :gone then :missing
      when :present then registered_pi_state(pane, session: session)
      else stopped_server?(session) ? :missing : :unreadable
      end
    rescue SystemCallError
      :unreadable
    end

    def registered_pi_state(pane, session:)
      stdout, stderr, _status = capture('agent', 'get', pane, session: session)
      document = response_document(stdout, stderr)
      return :unreadable unless document

      classify_registered_pi(pane, document, session: session)
    end

    def classify_registered_pi(pane, document, session:)
      return :dead if structured_error_code(document) == 'agent_not_found' && !document.key?('result')
      return :unreadable unless valid_registration?(document, pane)

      case pi_process_state(pane, session: session)
      when :pi then :alive
      when :shell then :dead
      else :unreadable
      end
    end

    def valid_registration?(document, pane)
      result = document['result']
      !document.key?('error') && result.is_a?(Hash) && registered_pi?(result['agent'], pane)
    end

    def registered_pi?(agent, pane)
      agent.is_a?(Hash) && agent['agent'] == 'pi' && agent['pane_id'] == pane &&
        %w[working idle done blocked].include?(agent['agent_status'])
    end

    def stopped_server?(session)
      stdout, _stderr, status = capture('status', '--json', session: session)
      return false unless status.success?

      document = JSON.parse(stdout)
      server = document['server'] if document.is_a?(Hash)
      server.is_a?(Hash) && server['running'] == false
    rescue JSON::ParserError
      false
    end

    def response_document(stdout, stderr)
      body = stdout.strip.empty? ? stderr : stdout
      document = JSON.parse(body)
      document if document.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end
end
