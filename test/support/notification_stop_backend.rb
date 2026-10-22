# frozen_string_literal: true

require_relative '../../lib/riddim/herdr'

module NotificationStopBackend
  def observe_pi_agent(*)
    state = ENV.fetch('RIDDIM_STATE_DIR')
    return [:dead, nil] if File.exist?(File.join(state, 'stopped'))

    [:alive, File.exist?(File.join(state, 'idle')) ? 'idle' : 'working']
  end

  def pane_tail(**)
    'Stable Pi prompt'
  end
end

Riddim::Herdr.singleton_class.prepend(NotificationStopBackend)
