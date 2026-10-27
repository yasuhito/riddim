# frozen_string_literal: true

require 'timeout'
require_relative '../../lib/riddim/schedules'

# Deterministic first-open/pre-flock boundary in a real CLI subprocess. No
# production environment seam, sleeping agent, or live state is involved.
module ScheduleInitializationPause
  def open_lock(*, **)
    result = super
    raise Errno::ENOSPC, 'injected after first lock open' if ENV['RIDDIM_INIT_FAULT'] == 'open'

    if ENV['RIDDIM_INIT_SIGNAL']
      File.write(ENV.fetch('RIDDIM_INIT_SIGNAL'), Process.pid.to_s)
      Timeout.timeout(10) { sleep 0.01 until File.exist?(ENV.fetch('RIDDIM_INIT_RELEASE')) }
    end
    result
  end

  def mark_ready(lock)
    raise Errno::ENOSPC, 'injected after empty document publication' if ENV['RIDDIM_INIT_FAULT'] == 'ready'

    super
    raise Errno::ENOSPC, 'injected after ready marker fsync' if ENV['RIDDIM_INIT_FAULT'] == 'committed'
  end
end

Riddim::Schedules::Store.singleton_class.prepend(ScheduleInitializationPause)
