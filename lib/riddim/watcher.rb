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

    # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
    def run(nonce:, exclude: [], interval: 0.25)
      raise ArgumentError, 'invalid watcher nonce' unless nonce.match?(/\A[0-9a-f]{32}\z/)
      raise ArgumentError, 'invalid interval' unless interval.positive?

      Ownership.verify_state_dir(Ownership.state_dir)
      # The directory lock survives unlink/replacement of the visible lock
      # file. Both are held for the observer's lifetime, never just at arm.
      File.open(Ownership.state_dir, File::RDONLY | File::NOFOLLOW) do |directory|
        bind!(directory)
        lock = File.join(Ownership.state_dir, '.notification-watcher.lock')
        File.open(lock, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |file|
          Result.verify_private_file!(file)
          bind!(file)
          observe(nonce, exclude, interval, directory, file)
        end
      end
    end

    def bind!(file)
      return if file.flock(File::LOCK_EX | File::LOCK_NB)

      raise Notifications::Error, 'watcher already bound to this home'
    end

    # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
    def observe(nonce, exclude, interval, directory, lock)
      ready = false
      last_beat = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        verify_owner!(directory, lock)
        entries = Notifications.scan.reject { |entry| exclude.include?(entry.id) }
        verify_owner!(directory, lock)
        unless ready
          stat = lock.stat
          announce('ready', nonce, lock: "#{stat.dev}:#{stat.ino}")
          ready = true
        end
        unless entries.empty?
          home_stat = directory.stat
          lock_stat = lock.stat
          announce('pending', nonce, ids: entries.map(&:id),
                   home: "#{home_stat.dev}:#{home_stat.ino}", lock: "#{lock_stat.dev}:#{lock_stat.ino}")
          break
        end
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now - last_beat >= 1
          announce('beat', nonce)
          last_beat = now
        end
        sleep interval
      end
    end

    def verify_owner!(directory, lock)
      verify_binding!(directory, Ownership.state_dir)
      verify_binding!(lock, File.join(Ownership.state_dir, '.notification-watcher.lock'))
      Result.verify_private_file!(lock)
      # File handles have size, not empty?. Inspect the locked inode itself.
      # rubocop:disable-next Style/ZeroLengthPredicate
      raise Notifications::Error, 'watcher lock marker is corrupt' unless lock.size.zero?
    end

    def verify_binding!(file, path)
      current = File.lstat(path)
      original = file.stat
      return if current.dev == original.dev && current.ino == original.ino && !current.symlink?

      raise Notifications::Error, 'watcher ownership changed during observation'
    end

    def announce(type, nonce, **extra)
      puts JSON.generate({ type: type, nonce: nonce }.merge(extra))
      $stdout.flush
    end
  end
end
