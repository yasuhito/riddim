# frozen_string_literal: true

require 'timeout'
require_relative '../../lib/riddim/notifications'

# Real CLI processes pause at the exact acknowledgement/listing interleaving
# that withdrew an intent marker under a lock-free reader. Each pause waits
# for a test-owned release file, bounded so a broken test cannot hang.
module NotificationAckInterleave
  def self.pause(name)
    directory = ENV.fetch('RIDDIM_TEST_INTERLEAVE')
    File.write(File.join(directory, name), '')
    Timeout.timeout(10) { sleep 0.01 until File.exist?(File.join(directory, "release-#{name}")) }
  end

  # The acknowledger holds the name lock with its intent and receipt durable.
  module Acknowledger
    def publish(path, content)
      super
      NotificationAckInterleave.pause('acknowledger') if File.basename(path).start_with?('.handled-')
    end
  end

  # The reader records whether it reached the listed markers or the name lock.
  module Reader
    def verify_marker_queue(...)
      NotificationAckInterleave.pause('reader') unless @paused
      @paused = true
      super
    end
  end

  # Waiting for the name lock is observable before the flock blocks.
  module LockWaiter
    def with_lock(name, **)
      File.write(File.join(ENV.fetch('RIDDIM_TEST_INTERLEAVE'), 'reader-locking'), '')
      super
    end
  end
end

case ENV.fetch('RIDDIM_TEST_INTERLEAVE_ROLE')
when 'acknowledger' then Riddim::Notifications.singleton_class.prepend(NotificationAckInterleave::Acknowledger)
when 'reader'
  Riddim::Notifications.singleton_class.prepend(NotificationAckInterleave::Reader)
  Riddim::Ownership.singleton_class.prepend(NotificationAckInterleave::LockWaiter)
end
