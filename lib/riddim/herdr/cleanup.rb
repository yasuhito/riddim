# frozen_string_literal: true

module Riddim
  # The confirmed cleanup surface of Riddim::Herdr, kept apart from the
  # read-and-create surface in herdr.rb: one explicit close of an exact pane
  # and a structured follow-up read that alone can prove the pane gone.
  # Pane-scoped by construction: a workspace is never closed here.
  module Herdr
    module_function

    # Classifies one pane get response body as the presence of exactly one
    # pane: :gone only for the structured pane_not_found error, :present only
    # when the response names this exact pane back, :unknown for every other
    # readable response, and :unparseable when the body is not JSON so the
    # caller can try its other stream. Herdr reports a missing pane as a
    # normal business response (real clients exit nonzero for it), so the
    # process exit status is never evidence here.
    def classify_pane_body(pane_id, body)
      document = JSON.parse(body)
      return :unknown unless document.is_a?(Hash)

      code = structured_error_code(document)
      return :gone if code == 'pane_not_found'
      return :unknown unless code.nil?

      result = document['result']
      return :unknown unless result.is_a?(Hash)

      pane_verdict(pane_id, result['pane'])
    rescue JSON::ParserError
      :unparseable
    end

    # The one structured error code of a response, when it names a code at all.
    def structured_error_code(document)
      error = document['error']
      code = error['code'] if error.is_a?(Hash)
      code if code.is_a?(String) && !code.empty?
    end

    # :present only when the response names this exact pane back; anything
    # else is ambiguity, never evidence either way.
    def pane_verdict(pane_id, pane)
      return :present if pane.is_a?(Hash) && pane['pane_id'] == pane_id

      :unknown
    end

    # The presence of one exact pane from a captured pane get. Herdr may put a
    # structured not-found response on stderr when stdout is empty. A nonempty
    # but invalid stdout is ambiguous, not permission to trust a second stream
    # as proof of absence (the same single-body caution as Firstmate's probe).
    def pane_presence(pane_id, stdout, stderr)
      body = stdout.strip.empty? ? stderr : stdout
      verdict = classify_pane_body(pane_id, body)
      verdict == :unparseable ? :unknown : verdict
    end

    # Read-only exact pane presence; a failed call or unreachable server is
    # unknown, never gone. Unlike agent-state, there is no stopped-server
    # shortcut: only pane_not_found confirms absence of this endpoint.
    def pane_presence_state(pane_id, session:)
      stdout, stderr, _status = capture('pane', 'get', pane_id, session: session)
      pane_presence(pane_id, stdout, stderr)
    rescue SystemCallError
      :unknown
    end

    # Issues one explicit close of the exact pane and confirms the pane is
    # gone with a structured pane get: only a pane_not_found error response
    # proves the endpoint gone. This is the only cleanup primitive the start
    # flow uses, and it never touches a workspace.
    def close_pane_confirmed(pane_id)
      _stdout, _stderr, status = capture('pane', 'close', pane_id)
      return false unless status.success?

      get_stdout, get_stderr, _get_status = capture('pane', 'get', pane_id)
      pane_presence(pane_id, get_stdout, get_stderr) == :gone
    rescue SystemCallError
      # The Herdr executable itself was unavailable: nothing is confirmed.
      false
    end
  end
end
