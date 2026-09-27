# frozen_string_literal: true

require_relative 'instruction_inbox'
require_relative 'send'

module Riddim
  # Independent of the supervisor's Pi notification watcher. The home lock
  # stays held for the process lifetime; only handled/ is receipt evidence.
  # rubocop:disable-next Metrics/ModuleLength
  module InstructionWatcher
    GRACE = 90
    MAX_ATTEMPTS = 3

    module_function

    # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Naming/PredicateMethod
    def run(interval: 5, once: false, now: -> { Time.now.to_i }, herdr: Herdr)
      home = File.expand_path(Ownership.state_dir)
      Ownership.verify_state_dir(home)
      File.open(home, File::RDONLY | File::NOFOLLOW) do |directory|
        File.open(File.join(home, '.instruction-watcher.lock'), File::RDWR | File::CREAT | File::NOFOLLOW,
                  0o600) do |lock|
          lock.chmod(0o600)
          return false unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          loop do
            verify_binding!(directory, home)
            verify_binding!(lock, File.join(home, '.instruction-watcher.lock'))
            scan(now: now.call, herdr: herdr)
            break if once

            sleep interval
          end
        end
      end
      true
    end

    def verify_binding!(file, path)
      current = File.lstat(path)
      original = file.stat
      return if !current.symlink? && current.dev == original.dev && current.ino == original.ino

      raise InstructionInbox::Error, 'instruction watcher lost its home or lock binding'
    end

    # rubocop:disable-next Metrics/MethodLength
    def scan(now:, herdr:)
      Dir.glob(File.join(Ownership.state_dir, '*.meta')).each do |record|
        name = File.basename(record, '.meta')
        next unless name.match?(Ownership::NAME_PATTERN)

        begin
          endpoint, generation = Ownership::Endpoint.resolve_snapshot(name)
          next unless Ownership.parse(Ownership::Endpoint.read_bytes(record))['task_mode'] == 'local-only'

          scan_owner(name, endpoint, generation, now, herdr)
        rescue InstructionInbox::Error
          raise
        rescue Ownership::Error => e
          raise InstructionInbox::Error, "instruction watcher cannot check #{name}: #{e.message}"
        end
      end
    end

    # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def scan_owner(name, endpoint, generation, now, herdr)
      # rubocop:disable-next Metrics/BlockLength
      # Herdr's notification subprocess inherits the same lifecycle lock as
      # Send.run, even if this observer dies during prompt delivery.
      Ownership.with_lock(name, inherit_on_exec: true) do
        return unless Ownership::Endpoint.resolve_snapshot(name) == [endpoint, generation]

        dir = InstructionInbox.path(name, generation)
        return unless File.exist?(dir) || File.symlink?(dir)

        InstructionInbox.verify_directory!(dir)
        records = Dir.glob(File.join(dir, '*.msg')).grep(%r{/\d+\.msg\z})
        record = records.min_by { |path| File.basename(path).to_i }
        return unless record
        raise InstructionInbox::Error, "instruction record is not a regular file: #{record}" if File.symlink?(record) || !File.file?(record)
        ring_state = File.join(dir, '.ring-state')
        base = File.basename(record)
        previous, count, last = read_retry_state(ring_state)
        return if now - File.stat(record).mtime.to_i < GRACE

        if previous != base
          count = 0
          last = 0
        end
        if count >= MAX_ATTEMPTS
          raise InstructionInbox::Error,
                "unhandled instruction exhausted retry budget: #{record}"
        end
        return if now - last < GRACE

        state = herdr.agent_state(endpoint.pane_id, session: endpoint.session)
        if %i[dead missing].include?(state)
          raise InstructionInbox::Error, "unhandled instruction has no live endpoint: #{record}"
        end
        raise InstructionInbox::Error, "instruction endpoint unverifiable: #{record}" unless state == :alive

        activity = herdr.busy_state(endpoint.pane_id, session: endpoint.session)
        return if activity == :busy
        raise InstructionInbox::Error, "worker activity unverifiable: #{record}" unless activity == :idle

        # No other lifecycle writer may rebind the endpoint while this lock is
        # held. Recheck the file after the backend probes: handled/ is the only
        # receipt and a notification never advances the queue.
        return unless File.file?(record) && !File.symlink?(record)
        return unless Ownership::Endpoint.resolve_snapshot(name) == [endpoint, generation]

        bell = InstructionInbox.notification(dir)
        Send.notify_worker(herdr, endpoint, bell, record)
        write_retry_state(ring_state, base, count + 1, now)
      end
    rescue InstructionInbox::Error
      raise
    rescue Ownership::Error, SystemCallError => e
      raise InstructionInbox::Error, "instruction watcher cannot check #{name}: #{e.message}"
    end

    # rubocop:disable-next Metrics/CyclomaticComplexity
    def read_retry_state(path)
      return [nil, 0, 0] unless File.exist?(path) || File.symlink?(path)

      raw = File.open(path, File::RDONLY | File::NOFOLLOW, &:read)
      fields = /\A(\d+\.msg)\t(\d+)\t(\d+)\n\z/.match(raw)
      raise InstructionInbox::Error, "invalid instruction retry state: #{path}" unless fields

      [fields[1], fields[2].to_i, fields[3].to_i]
    end

    def write_retry_state(path, base, count, now)
      temp = "#{path}.#{Process.pid}.tmp"
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.write("#{base}\t#{count}\t#{now}\n")
        file.flush
        file.fsync
      end
      File.rename(temp, path)
      File.open(File.dirname(path), &:fsync)
    ensure
      File.delete(temp) if temp && File.exist?(temp)
    end

    # Launch a standalone observer on the selected home, not a Pi hook. A
    # second launch loses the lock and exits; a later send can replace a dead
    # observer. Operators can also run watch-instructions under a supervisor.
    # rubocop:disable-next Metrics/MethodLength
    def start
      home = File.expand_path(Ownership.state_dir)
      should_start = File.open(File.join(home, '.instruction-watcher.lock'),
                               File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |lock|
        lock.flock(File::LOCK_EX | File::LOCK_NB)
      end
      return unless should_start

      pid = Process.spawn({ 'RIDDIM_STATE_DIR' => home },
                          RbConfig.ruby, File.expand_path('../../bin/riddim', __dir__), 'watch-instructions',
                          in: File::NULL, out: File::NULL,
                          err: [File.join(home, '.instruction-watcher.log'), 'a'], pgroup: true)
      Process.detach(pid)
    end
  end
end
