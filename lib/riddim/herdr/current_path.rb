# frozen_string_literal: true

module Riddim
  # Read-only exact-pane foreground directory observation.
  module Herdr
    module_function

    # pane.cwd can describe the shell rather than its foreground subshell;
    # only foreground_cwd answers the current foreground process's location.
    # Unknown is a literal verdict, not a guessed worktree or an empty path.
    def current_path(pane_id, session:)
      stdout, _stderr, status = capture('pane', 'get', pane_id, session: session)
      return :unknown unless status.success?

      pane = matching_path_pane(JSON.parse(stdout), pane_id)
      path = pane['foreground_cwd'] if pane
      valid_foreground_path?(path) ? path : :unknown
    rescue SystemCallError, JSON::ParserError
      :unknown
    end

    def matching_path_pane(document, pane_id)
      return unless document.is_a?(Hash) && !document.key?('error')

      result = document['result']
      pane = result['pane'] if result.is_a?(Hash)
      pane if pane.is_a?(Hash) && pane['pane_id'] == pane_id
    end

    def valid_foreground_path?(path)
      path.is_a?(String) && path.valid_encoding? && path.start_with?('/') && !path.match?(/[[:cntrl:]]/)
    end
  end
end
