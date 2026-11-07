# frozen_string_literal: true

require_relative 'notification_history_backend'
require_relative '../../lib/riddim/watcher'

module NotificationBackpressureBackend
  def announce(type, ...)
    File.write(File.join(Riddim::Ownership.state_dir, 'checkpoint-attempt'), type) if %w[progress beat].include?(type)
    super
  end
end

Riddim::Watcher.singleton_class.prepend(NotificationBackpressureBackend)
