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
      Dir.glob(File.join(Ownership.state_dir, '*.inbox')).each do |dir|
        match = /\A([a-z][a-z0-9_-]{0,31})\.(s\d+\.\d+\.\d+)\.inbox\z/.match(File.basename(dir))
        next unless match

        name, generation = match.captures
        begin
          InstructionInbox.verify_directory!(dir)
          next unless unreceived_instructions?(dir)

          endpoint, current_generation = Ownership::Endpoint.resolve_snapshot(name)
          next unless current_generation == generation

          scan_owner(name, endpoint, generation, now, herdr)
        rescue InstructionInbox::Error
          raise
        rescue Ownership::Error => e
          raise InstructionInbox::Error, "instruction watcher cannot check #{name}: #{e.message}"
        end
      end
    end

    def unreceived_instructions?(dir)
      return true if Dir.glob(File.join(dir, '*.msg')).any?

      Dir.glob(File.join(dir, '*.msg.expected')).any? do |expected|
        receipt = File.join(dir, 'handled', File.basename(expected, '.expected'))
        !File.file?(receipt) || File.symlink?(receipt)
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
        handled = File.join(dir, 'handled')
        InstructionInbox.verify_directory!(handled)
        ring_state = File.join(dir, '.ring-state')
        ensure_retry_state!(ring_state)
        previous, count, last = read_retry_state(ring_state)
        verify_record_receipt!(dir, previous, count)
        verify_published_records!(dir)
        records = Dir.glob(File.join(dir, '*.msg')).grep(%r{/\d+\.msg\z})
        record = records.min_by { |path| File.basename(path).to_i }
        return unless record

        if File.symlink?(record) || !File.file?(record)
          raise InstructionInbox::Error, "instruction record is not a regular file: #{record}"
        end

        mode = Ownership.parse(Ownership::Endpoint.read_bytes(Ownership.record_path(name)))['task_mode']
        raise InstructionInbox::Error, "pending instruction owner mode changed: #{record}" unless mode == 'local-only'

        base = File.basename(record)
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
        unless File.file?(record) && !File.symlink?(record)
          verify_record_receipt!(dir, base, 1)
          return
        end
        return unless Ownership::Endpoint.resolve_snapshot(name) == [endpoint, generation]

        bell = InstructionInbox.notification(dir)
        write_retry_state(ring_state, base, count + 1, now)
        Send.notify_worker(herdr, endpoint, bell, record)
      end
    rescue InstructionInbox::Error
      raise
    rescue Ownership::Error, SystemCallError => e
      raise InstructionInbox::Error, "instruction watcher cannot check #{name}: #{e.message}"
    end

    def read_retry_state(path)
      raw = File.open(path, File::RDONLY | File::NOFOLLOW, &:read)
      fields = /\A(\d+\.msg)\t(\d+)\t(\d+)\n\z/.match(raw)
      raise InstructionInbox::Error, "invalid instruction retry state: #{path}" unless fields

      [fields[1], fields[2].to_i, fields[3].to_i]
    end

    # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
    def ensure_retry_state!(path)
      marker = "#{path}.required"
      if File.exist?(marker) || File.symlink?(marker)
        unless File.file?(marker) && !File.symlink?(marker)
          raise InstructionInbox::Error, "invalid instruction retry marker: #{marker}"
        end

        return
      end

      write_retry_state(path, '0.msg', 0, 0) unless File.exist?(path) || File.symlink?(path)
      read_retry_state(path)
      File.open(marker, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.flush
        file.fsync
      end
      File.open(File.dirname(path), &:fsync)
    end

    def verify_record_receipt!(dir, base, count)
      return if count.zero? && base == '0.msg'

      pending = File.join(dir, base)
      receipt = File.join(dir, 'handled', base)
      return if File.file?(pending) && !File.symlink?(pending)
      return if File.file?(receipt) && !File.symlink?(receipt)

      raise InstructionInbox::Error, "instruction missing without handled receipt: #{pending}"
    end

    def verify_published_records!(dir)
      Dir.glob(File.join(dir, '*.msg.expected')).each do |expected|
        base = File.basename(expected, '.expected')
        unless base.match?(/\A\d+\.msg\z/) && File.file?(expected) && !File.symlink?(expected)
          raise InstructionInbox::Error, "invalid instruction publication marker: #{expected}"
        end

        verify_record_receipt!(dir, base, 1)
      end
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
