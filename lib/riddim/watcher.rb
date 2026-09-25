# frozen_string_literal: true

require 'json'
require_relative 'notifications'

module Riddim
  # One observer per selected home. The lock spans every scan and wait; no
  # Worker command or Herdr input is involved. A new process must acquire the
  # lock and complete a scan before it can announce readiness.
  module Watcher
    IDENTITY = /\A[a-z][a-z0-9_-]{0,31}\.s\d+\.\d+\.\d+\.[1-9]\d*\z/

    module_function

    # rubocop:disable-next Metrics/MethodLength
    def run(nonce:, exclude: [], interval: 0.25)
      raise ArgumentError, 'invalid watcher nonce' unless nonce.match?(/\A[0-9a-f]{32}\z/)
      raise ArgumentError, 'invalid interval' unless interval.positive?

      Ownership.verify_state_dir(Ownership.state_dir)
      lock = File.join(Ownership.state_dir, '.notification-watcher.lock')
      File.open(lock, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |file|
        Result.verify_private_file!(file)
        unless file.flock(File::LOCK_EX | File::LOCK_NB)
          raise Notifications::Error, 'watcher already bound to this home'
        end

        observe(nonce, exclude, interval)
      end
    end

    # rubocop:disable-next Metrics/MethodLength
    def observe(nonce, exclude, interval)
      ready = false
      loop do
        entries = Notifications.scan.reject { |entry| exclude.include?(entry.id) }
        unless ready
          announce('ready', nonce)
          ready = true
        end
        unless entries.empty?
          announce('pending', nonce, ids: entries.map(&:id))
          break
        end
        sleep interval
      end
    end

    def announce(type, nonce, **extra)
      puts JSON.generate({ type: type, nonce: nonce }.merge(extra))
      $stdout.flush
    end
  end
end
