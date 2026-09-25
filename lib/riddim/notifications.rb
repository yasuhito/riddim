# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'securerandom'
require_relative 'result'

module Riddim
  # A manually reconciled, private report inbox. Classification is independent
  # of Worker reporting and never asserts Pi delivery or Git readiness.
  # The scan is deliberately serialized against the existing name lock.
  # rubocop:disable-next Metrics/ModuleLength
  module Notifications
    class Error < Ownership::Error; end

    ACTIONABLE = %w[done blocked failed needs-decision].freeze
    Entry = Data.define(:id, :task, :generation, :sequence, :event)

    module_function

    def directory
      File.join(File.expand_path(Ownership.state_dir), '.notifications')
    end

    def scan
      Ownership.verify_state_dir(Ownership.state_dir)
      ensure_directory
      Dir.children(Ownership.state_dir).grep(/\A[a-z][a-z0-9_-]{0,31}\.meta\z/).sort.each do |file|
        name = file.delete_suffix('.meta')
        Ownership.with_lock(name) { classify(name) }
      end
      pending
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def pending
      return [] unless File.exist?(directory) || File.symlink?(directory)

      verify_directory
      Dir.children(directory).grep(/\.json\z/).sort.map do |filename|
        path = File.join(directory, filename)
        bytes = private_read(path)
        row = JSON.parse(bytes)
        raise Error, "invalid notification at #{path}" unless valid_entry?(row, filename)

        Entry.new(**row.transform_keys(&:to_sym))
      end
    rescue JSON::ParserError => e
      raise Error, "invalid notification: #{e.message}"
    end

    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def valid_entry?(row, filename)
      row.is_a?(Hash) && row.keys.sort == %w[event generation id sequence task] &&
        row['id'] == filename.delete_suffix('.json') &&
        row['task'].is_a?(String) && row['task'].match?(Ownership::NAME_PATTERN) &&
        row['generation'].is_a?(String) && row['generation'].match?(Result::GENERATION) &&
        row['sequence'].is_a?(Integer) && row['sequence'].positive? &&
        ACTIONABLE.include?(row['event']) &&
        row['id'] == identity(row['task'], row['generation'], row['sequence'])
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def classify(name)
      snapshot, fields, bytes = Result.task_record(name)
      return unless fields['status_protocol'] == Result::STATUS_PROTOCOL

      generation = snapshot.last
      path = Result.path(name, generation)
      # Result's parser refuses partial, malformed, oversized, or symlinked input.
      text = File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        Result.verify_private_file!(file)
        content = file.read(Result::MAX_BYTES + 1) || ''
        Result.parse_events(content)
        content
      end
      cursor_path = File.join(directory, ".cursor-#{name}-#{generation}")
      cursor = read_cursor(cursor_path)
      offset = cursor.fetch('offset', 0)
      prefix = text.byteslice(0, offset)
      raise Error, "status changed before classified position for #{name}" if
        prefix.nil? || (cursor['digest'] && cursor['digest'] != Digest::SHA256.hexdigest(prefix))

      # The same name lock used by report and lifecycle writers protects the
      # ownership recheck and every publication. Never attribute a read to a
      # replacement generation or to modified record bytes.
      unless Ownership::Endpoint.unchanged?(name, snapshot) &&
             Ownership::Endpoint.read_bytes(Ownership.record_path(name)) == bytes
        raise Error, "ownership changed during notification scan for #{name}"
      end

      position = 0
      text.lines.each_with_index do |line, index|
        position += line.bytesize
        next if position <= offset

        event = line.split(' ', 2).first
        next unless ACTIONABLE.include?(event)

        entry = Entry.new(id: identity(name, generation, index + 1), task: name,
                          generation: generation, sequence: index + 1, event: event)
        publish(File.join(directory, "#{entry.id}.json"), "#{JSON.generate(entry.to_h)}\n")
      end
      return if position == offset

      # The cursor is only an optimization. The queue is durable first; on a
      # crash before this replacement, replay sees the same event identities.
      replace(cursor_path, "#{JSON.generate(offset: position, digest: Digest::SHA256.hexdigest(text))}\n")
    end

    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

    def identity(name, generation, sequence)
      "#{name}.#{generation}.#{sequence}"
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def read_cursor(path)
      return {} unless File.exist?(path) || File.symlink?(path)

      row = JSON.parse(private_read(path))
      unless row.is_a?(Hash) && row.keys.sort == %w[digest offset] &&
             row['offset'].is_a?(Integer) && row['offset'] >= 0 &&
             row['digest'].is_a?(String) && row['digest'].match?(/\A[0-9a-f]{64}\z/)
        raise Error, "invalid notification cursor at #{path}"
      end

      row
    rescue JSON::ParserError => e
      raise Error, "invalid notification cursor: #{e.message}"
    end

    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    def private_read(path)
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        Result.verify_private_file!(file)
        file.read(Result::MAX_BYTES + 1).tap do |bytes|
          raise Error, "notification evidence is oversized at #{path}" if bytes.bytesize > Result::MAX_BYTES
        end
      end
    end

    def ensure_directory
      Dir.mkdir(directory, 0o700) unless File.exist?(directory) || File.symlink?(directory)
      verify_directory
    end

    def verify_directory
      stat = File.lstat(directory)
      private_directory = stat.directory? && stat.uid == Process.euid && stat.mode.nobits?(0o077)
      raise Error, 'notification directory is not private and real' unless private_directory
    end

    # rubocop:disable-next Metrics/MethodLength
    def publish(path, content)
      if File.exist?(path) || File.symlink?(path)
        raise Error, "notification identity collision at #{path}" unless private_read(path) == content

        return
      end
      temp = stage(path, content)
      begin
        File.link(temp, path)
        sync_directory
      rescue Errno::EEXIST
        raise Error, "notification identity collision at #{path}" unless private_read(path) == content
      ensure
        File.unlink(temp)
      end
    end

    def replace(path, content)
      raise Error, "notification cursor was replaced at #{path}" if File.symlink?(path)

      temp = stage(path, content)
      begin
        File.rename(temp, path)
        sync_directory
      ensure
        FileUtils.rm_f(temp)
      end
    end

    def stage(path, content)
      temp = "#{path}.#{SecureRandom.hex(12)}.tmp"
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.write(content)
        file.flush
        file.fsync
      end
      temp
    end

    def sync_directory
      File.open(directory, File::RDONLY, &:fsync)
    end
  end
end
