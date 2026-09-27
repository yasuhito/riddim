# frozen_string_literal: true

require 'fileutils'
require_relative 'ownership'

module Riddim
  # A generation-scoped instruction queue. The ownership lock serializes
  # writers with retirement and replacement; handled/ is the worker's receipt.
  module InstructionInbox
    GENERATION = /\As\d+\.\d+\.\d+\z/

    class Error < Ownership::Error; end

    module_function

    def path(name, generation)
      raise Error, 'invalid instruction generation' unless generation.is_a?(String) && generation.match?(GENERATION)

      File.join(File.expand_path(Ownership.state_dir), "#{Ownership.validated_name(name)}.#{generation}.inbox")
    end

    def enqueue(name, generation, message)
      dir = path(name, generation)
      prepare(dir)
      record = File.join(dir, format('%09d.msg', next_sequence(dir)))
      publish_expectation(record)
      publish(record, message)
      record
    rescue SystemCallError, Ownership::Error => e
      raise Error, "instruction could not be stored in #{dir}: #{e.message}"
    end

    def publish_expectation(record)
      expected = "#{record}.expected"
      File.open(expected, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
        file.flush
        file.fsync
      end
      sync_record_directory(expected)
    end

    def next_sequence(dir)
      (Dir.children(dir) + Dir.children(File.join(dir, 'handled'))).filter_map do |entry|
        match = /\A(\d+)\.msg(?:\.expected)?\z/.match(entry)
        Integer(match[1], 10) if match
      end.max.to_i + 1
    end

    def publish(record, message)
      temp = File.join(File.dirname(record), ".staging.#{Process.pid}.#{SecureRandom.hex(8)}")
      begin
        Ownership.stage_record(temp, "schema=riddim-instruction.v1\n--\n#{message}")
        Ownership.link_no_replace(temp, record)
        sync_record_directory(record)
      ensure
        Ownership.discard_temp(temp)
      end
    end

    def sync_record_directory(record)
      File.open(File.dirname(record), &:fsync)
    rescue SystemCallError => e
      raise Error, "instruction may already exist at #{record}; inspect before retrying: #{e.message}"
    end

    def prepare(dir)
      [dir, File.join(dir, 'handled')].each { |path| prepare_directory(path) }
    end

    def prepare_directory(path)
      begin
        Dir.mkdir(path, 0o700)
        File.open(File.dirname(path), &:fsync)
      rescue Errno::EEXIST
        verify_directory!(path)
      end
      File.chmod(0o700, path)
    end

    def verify_directory!(path)
      return if !File.symlink?(path) && File.directory?(path)

      raise Error, "instruction directory is not a real directory: #{path}"
    end

    def notification(dir)
      # No untrusted payload or terminal control bytes go through the prompt.
      unless dir.ascii_only? && dir.match?(/\A[\x20-\x7e]+\z/)
        raise Error,
              'instruction path contains nonprintable characters'
      end

      ": Riddim instruction waiting: list #{dir.inspect}/*.msg in numeric order; " \
        "read each after --, act on it, then mv it to #{dir.inspect}/handled/. " \
        'If none remain, do nothing.'
    end

    def receive_contract(name, generation)
      dir = path(name, generation)
      <<~TEXT

        # Instruction inbox
        New instructions for this worker are stored at #{dir.inspect}/*.msg. List pending .msg files in numeric order. Read the text after the -- line in each file, act on it, then move that file into #{dir.inspect}/handled/ to acknowledge it. Do not act on a notification alone: repeated notifications do not create new instructions. Check this inbox again when notified. Report any inability to read or acknowledge an instruction.
      TEXT
    end
  end
end
