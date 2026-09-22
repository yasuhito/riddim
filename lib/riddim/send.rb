# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'

module Riddim
  # The ownership-safe direct prompt corridor. The unlocked read refuses a
  # missing record without creating a lock file; the locked re-read is the
  # routing authority, and the lock remains held until Herdr returns so every
  # cooperating lifecycle writer observes the delivery as one serialized use
  # of that endpoint generation.
  module Send
    module_function

    def run(name, message, endpoint_records: Ownership::Endpoint, locks: Ownership, herdr: Herdr)
      endpoint_records.resolve(name)
      locks.with_lock(name, inherit_on_exec: true) do
        endpoint = endpoint_records.resolve(name)
        herdr.prompt(endpoint.pane_id, message, session: endpoint.session)
      end
    end
  end
end
