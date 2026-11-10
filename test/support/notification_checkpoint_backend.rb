# frozen_string_literal: true

require_relative '../../lib/riddim/watcher'

# Force legal checkpoint interleaving on the real native wire without sleeps.
# Slow-scan timing/ownership is covered separately by WatcherHistoryTest.
module NotificationCheckpointBackend
  def announce(type, nonce, **extra)
    if type == 'ready'
      home = Riddim::Schedules::Store.identity(File.stat(Riddim::Ownership.state_dir))
      super('progress', nonce, home: home, lock: extra.fetch(:lock))
    elsif type == 'pending'
      super('beat', nonce)
    end
    super
  end
end

Riddim::Watcher.singleton_class.prepend(NotificationCheckpointBackend)
