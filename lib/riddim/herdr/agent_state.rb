# frozen_string_literal: true

module Riddim
  # Read-only classification of the exact pane recorded for a Pi agent.
  module Herdr
    module_function

    # Read-only, Pi-only subset of Firstmate's recovery-grade Herdr verdicts.
    # :missing covers an absent pane OR a stopped server: it does not prove an
    # endpoint was destroyed and never licenses a lifecycle mutation by itself.
    def agent_state(pane, session:)
      observe_pi_agent(pane, session: session).first
    end

    # A stricter Pi-only subset of Firstmate's native busy classifier. Native
    # idle is an observation, never a claim that a turn or tool has completed.
    def busy_state(pane, session:)
      state, raw_status = observe_pi_agent(pane, session: session)
      return :unknown unless state == :alive

      case raw_status
      when 'working' then :busy
      when 'idle', 'done', 'blocked' then :idle
      else :unknown
      end
    end

    def observe_pi_agent(pane, session:)
      stdout, stderr, _status = capture('pane', 'get', pane, session: session)
      case pane_presence(pane, stdout, stderr)
      when :gone then [:missing, nil]
      when :present then registered_pi_observation(pane, session: session)
      else [stopped_server?(session) ? :missing : :unreadable, nil]
      end
    rescue SystemCallError
      [:unreadable, nil]
    end

    def registered_pi_observation(pane, session:)
      stdout, stderr, _status = capture('agent', 'get', pane, session: session)
      document = response_document(stdout, stderr)
      return [:unreadable, nil] unless document

      classify_registered_pi(pane, document, session: session)
    end

    def classify_registered_pi(pane, document, session:)
      return [:dead, nil] if structured_error_code(document) == 'agent_not_found' && !document.key?('result')
      return [:unreadable, nil] unless valid_registration?(document, pane)

      raw_status = document.fetch('result').fetch('agent').fetch('agent_status')
      case pi_process_state(pane, session: session)
      when :pi then [:alive, raw_status]
      when :shell then [:dead, nil]
      else [:unreadable, nil]
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
      server_running_state(session: session) == :stopped
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
