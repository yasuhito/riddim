# frozen_string_literal: true

require_relative 'notification_stop_backend'

# Exercise real Herdr.capture/Open3 subprocesses, not a sleep in the scanner.
# Other observations delegate to the native-state fixture, never live Herdr.
module NotificationSlowBackend
  def observe_pi_agent(pane, session:)
    return super unless File.exist?(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'herdr-delay'))

    3.times { capture('riddim-test-probe', pane, session: session) }
    [:alive, 'working']
  end
end

Riddim::Herdr.singleton_class.prepend(NotificationSlowBackend)
