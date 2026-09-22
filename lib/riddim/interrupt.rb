# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'

module Riddim
  # The ownership-safe lifecycle corridor for Pi's single-key interrupt. The
  # unlocked read refuses a missing record without creating a lock file. The
  # locked re-read is the routing authority, and the per-name lock remains held
  # through delivery and the registration postcondition so a cooperating
  # lifecycle writer cannot rebind the name during the operation. Herdr
  # subprocesses inherit the lock descriptor, so a subprocess still finishing
  # after an abrupt controller exit keeps the name bound until it exits.
  module Interrupt
    module_function

    def run(name, endpoint_records: Ownership::Endpoint, locks: Ownership, herdr: Herdr)
      endpoint_records.resolve(name)
      locks.with_lock(name, inherit_on_exec: true) do
        endpoint = endpoint_records.resolve(name)
        herdr.interrupt(endpoint.pane_id, session: endpoint.session)
      end
    end
  end
end
