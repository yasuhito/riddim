# frozen_string_literal: true

require_relative '../../lib/riddim/herdr'

module NotificationStopBackend
  def agent_state(*)
    File.exist?(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'stopped')) ? :dead : :alive
  end
end

Riddim::Herdr.singleton_class.prepend(NotificationStopBackend)
