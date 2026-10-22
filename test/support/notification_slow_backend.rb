# frozen_string_literal: true

require_relative '../../lib/riddim/herdr'

# Exercise real Herdr.capture/Open3 subprocesses, not a sleep in the scanner.
module NotificationSlowBackend
  def observe_pi_agent(pane, session:)
    return super unless File.exist?(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'herdr-delay'))

    3.times { capture('riddim-test-probe', pane, session: session) }
    [:alive, 'working']
  end
end

Riddim::Herdr.singleton_class.prepend(NotificationSlowBackend)
