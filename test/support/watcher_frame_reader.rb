# frozen_string_literal: true

require 'json'
require 'timeout'

# Test-only reader for a single bound observer stream. Checkpoints are not
# readiness or notifications, and cannot renew the caller's overall deadline.
module WatcherFrameReader
  def self.read(stdout, nonce:, expected:, timeout: 5)
    Timeout.timeout(timeout) do
      loop do
        frame = JSON.parse(stdout.gets || raise('watcher exited before frame'))
        raise 'watcher frame nonce mismatch' unless frame.is_a?(Hash) && frame['nonce'] == nonce
        next if %w[progress beat].include?(frame['type'])
        raise "expected watcher #{expected}, got #{frame['type'].inspect}" unless frame['type'] == expected

        return frame
      end
    end
  end
end
