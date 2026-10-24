# frozen_string_literal: true

module Riddim
  # Generation-local status proof before and after moving local main.
  module MergeLocal
    module_function

    def verify_protocol!(fields)
      return if fields['status_protocol'] == Result::STATUS_PROTOCOL

      raise Refused, 'worker does not use the locked report protocol; merge manually after review'
    end

    def verify_done_report!(name, generation)
      status = Result.read_status(Result.path(name, generation))
      return if Result.ungated_done_status?(status)

      diagnostics = Result.status_diagnostics(status, name)
      raise Refused, "worker has no ungated done report; refusing the merge: #{diagnostics}"
    end

    # Direct file appends bypass the name lock. If one races with Git itself,
    # the moved ref cannot be undone safely, so report it instead of success.
    def verify_post_merge_report!(name, generation, landed)
      return if Result.ungated_done?(name, generation)

      raise Refused, "worker opened a decision during landing; local main may have moved to #{landed}"
    rescue Result::Error, SystemCallError => e
      raise Refused, "status unreadable after landing; local main may have moved to #{landed}: #{e.message}"
    end
  end
end
