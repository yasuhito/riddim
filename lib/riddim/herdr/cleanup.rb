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

      pane_verdict(pane_id, document.dig('result', 'pane'))
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

    # The presence of one exact pane from a captured pane get: the stdout body
    # first, then stderr, because the structured not-found error may arrive on
    # either stream. Anything unreadable on both streams is :unknown, which
    # never proves a pane gone.
    def pane_presence(pane_id, stdout, stderr)
      [stdout, stderr].each do |body|
        verdict = classify_pane_body(pane_id, body)
        return verdict unless verdict == :unparseable
      end

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
