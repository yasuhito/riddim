# frozen_string_literal: true

require 'json'
require 'fileutils'
require 'securerandom'
require_relative '../result'

module Riddim
  module Schedules
    # One atomic document commits cadence and occurrence together. Directory and
    # lock descriptors stay pinned throughout every read-modify-write operation.
    # rubocop:disable-next Metrics/ModuleLength
    module Store
      MAX_BYTES = 4_194_304
      FILE = '.scheduled-prompts.json'
      LOCK = '.scheduled-prompts.lock'
      WATCHER = '.notification-watcher.lock'
      SCHEMA = 'riddim.scheduled-prompts.v1'

      # Reject duplicate JSON object keys before converting to mutable Hashes.
      class UniqueKeys < Hash
        def []=(key, value)
          raise Error, "duplicate schedule field #{key}" if key?(key)

          super
        end
      end

      module_function

      def identity(stat)
        "#{stat.dev}:#{stat.ino}"
      end

      def verify_binding!(file, path, shared: false)
        stat = File.lstat(path)
        return if !stat.symlink? && identity(stat) == identity(file.stat)

        raise(shared ? SourceChanged : Error, "scheduled prompt ownership changed: #{path}")
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
      def transaction(expected: nil, create: false, &)
        home = File.expand_path(Ownership.state_dir)
        File.open(home, File::RDONLY | File::NOFOLLOW) do |directory|
          stat = directory.stat
          raise Error, 'scheduled prompt home must be private and owned' unless
            stat.directory? && stat.uid == Process.euid && stat.mode.nobits?(0o077)

          base = "/proc/self/fd/#{directory.fileno}"
          File.open(File.join(base, WATCHER), File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |watcher|
            verify_lock!(watcher)
            with_lock(base, create: create) do |lock|
              Result.verify_private_file!(lock)
              raise Error, 'scheduled prompt lock must not be hard-linked' unless lock.stat.nlink == 1

              lock.flock(File::LOCK_EX)
              verify = lambda do
                verify_binding!(directory, home, shared: true)
                verify_binding!(watcher, File.join(home, WATCHER), shared: true)
                verify_binding!(lock, File.join(home, LOCK))
                verify_lock!(watcher)
                store_phase(lock)
              end
              bindings = { 'home' => identity(directory.stat), 'watcher_lock' => identity(watcher.stat),
                           'store_lock' => identity(lock.stat) }
              verify.call
              check_expected!(expected, bindings)
              transact(base, bindings, verify, lock, &)
            end
          end
        end
      rescue Errno::ENOENT
        raise Error, 'scheduled prompt source missing; use the original verified watcher home and session metadata'
      end

      def open_lock(path, create:)
        flags = File::RDWR | File::NOFOLLOW
        flags |= File::CREAT if create
        File.open(path, flags, 0o600)
      end

      def with_lock(base, create:)
        lock = open_lock(File.join(base, LOCK), create: create)
        begin
          yield lock
        ensure
          lock.close
        end
      end

      # Empty means provably uninitialized: no nonempty document may be written
      # before a durable '1' marker. Only a validated EMPTY initial document may
      # be recovered in this phase. A ready marker plus missing data is loss,
      # never permission to initialize over an established source.
      def store_phase(lock)
        Result.verify_private_file!(lock)
        lock.rewind
        phase = lock.read(2) || ''
        raise Error, 'scheduled prompt initialization marker is corrupt' unless ['', '1'].include?(phase)

        phase
      end

      def mark_ready(lock)
        lock.rewind
        lock.write('1')
        lock.flush
        lock.fsync
      end

      def verify_lock!(file)
        Result.verify_private_file!(file)
        # File handles have size, not empty?.
        # rubocop:disable-next Style/ZeroLengthPredicate
        raise Error, 'scheduled prompt lock marker is corrupt' unless file.size.zero?
      end

      def check_expected!(expected, bindings)
        return unless expected
        return if expected == bindings.values_at('home', 'watcher_lock')

        raise Error, 'scheduled prompt source does not match the original home/watcher lock'
      end

      def transact(base, bindings, verify, lock)
        path = File.join(base, FILE)
        document = initialize_document(path, bindings, base, verify, lock)
        before = JSON.generate(document)
        result = yield document.fetch('schedules')
        content = JSON.generate(document)
        raise Error, 'scheduled prompt store is oversized' if content.bytesize > MAX_BYTES

        verify.call
        replace(path, content, base, verify) unless content == before
        result
      end

      def initialize_document(path, bindings, base, verify, lock)
        initializing = store_phase(lock).empty?
        document = load_document(path, bindings, initializing: initializing)
        if initializing
          raise Error, 'uninitialized scheduled prompt store contains work; recover the original source' unless
            document.fetch('schedules').empty?

          replace(path, JSON.generate(document), base, verify)
          mark_ready(lock)
        end
        lock.fsync # Also finish an earlier interrupted ready-marker fsync.
        document
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
      def load_document(path, bindings, initializing:)
        unless File.exist?(path) || File.symlink?(path)
          raise Error, 'scheduled prompt store is missing; recover the original source, never initialize over it' unless
            initializing

          return { 'schema' => SCHEMA, **bindings, 'schedules' => [] }
        end

        document = File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
          Result.verify_private_file!(file)
          bytes = file.read(MAX_BYTES + 1) || ''
          raise Error, 'scheduled prompt store is oversized' if bytes.bytesize > MAX_BYTES

          plain(JSON.parse(bytes, object_class: UniqueKeys))
        end
        Validation.document!(document, bindings)
        document
      rescue JSON::ParserError => e
        raise Error, "corrupt scheduled prompt store: #{e.message}"
      end

      def plain(value)
        case value
        when Hash then value.to_h { |key, item| [key, plain(item)] }
        when Array then value.map { |item| plain(item) }
        else value
        end
      end

      # rubocop:disable-next Metrics/MethodLength
      def replace(path, content, base, verify)
        temp = "#{path}.#{SecureRandom.hex(12)}.tmp"
        begin
          File.open(temp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
            file.write(content)
            file.flush
            file.fsync
          end
          verify.call
          File.rename(temp, path)
          File.open(base, File::RDONLY, &:fsync)
        ensure
          FileUtils.rm_f(temp)
        end
      end
    end
  end
end
