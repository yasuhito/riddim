# frozen_string_literal: true

require_relative 'ownership'
require_relative 'worktree'

module Riddim
  # Local-only handoff: a worker event is a claim. Only an independently
  # verified, committed, clean, fast-forwardable branch is ready for review.
  # This is not Firstmate's reconciled current crew state or a merge authority.
  module Result
    class Error < Ownership::Error; end

    GENERATION = /\As\d+\.\d+\.\d+\z/
    EVENT = /\A(done|blocked|failed|needs-decision|working|paused) \[at=\d+\]: ([^\n\r\x00]+)\z/
    MAX_BYTES = 65_536
    STATUS_PROTOCOL = 'locked-v1'
    Event = Data.define(:sequence, :kind, :end_offset)
    Status = Data.define(:last, :open_gate, :events)

    module_function

    def path(name, generation)
      raise Error, 'invalid result generation' unless generation.is_a?(String) && generation.match?(GENERATION)

      File.join(Ownership.state_dir, "#{Ownership.validated_name(name)}.#{generation}.status")
    end

    def publish(name, generation)
      file = path(name, generation)
      Ownership.publish(file, '')
      file
    end

    def read(name)
      snapshot, fields, bytes = task_record(name)
      status = read_status(path(name, snapshot.last))
      outcome = describe(status, name, fields)
      unchanged = Ownership::Endpoint.unchanged?(name, snapshot) &&
                  Ownership::Endpoint.read_bytes(Ownership.record_path(name)) == bytes
      unchanged ? outcome : 'unknown (ownership changed)'
    rescue SystemCallError, Worktree::Error => e
      "unknown (#{e.message})"
    end

    def task_record(name)
      snapshot = Ownership::Endpoint.resolve_snapshot(name)
      bytes = Ownership::Endpoint.read_bytes(Ownership.record_path(name))
      fields = Ownership.parse(bytes)
      raise Error, 'result is available only for local-only tasks' unless fields['task_mode'] == 'local-only'
      raise Error, 'result record changed while reading' unless fields['spawn_gen'] == snapshot.last

      [snapshot, fields, bytes]
    end

    # Whether the generation-local status file ends with an ungated done
    # event: the last event is done and no blocked, failed, or
    # needs-decision event precedes it. Teardown and merge-local gate on this
    # one predicate, so a later done cannot clear an open decision in either.
    def ungated_done?(name, generation)
      status = read_status(path(name, generation))
      status.last&.start_with?('done ') && !status.open_gate
    end

    def describe(status, name, fields)
      event = status.last
      return 'unreported' unless event
      return "reported: #{event}" unless event.start_with?('done ')

      ready = !status.open_gate && ready?(name, fields)
      ready ? "ready: #{event}" : "reported (not ready): #{event}"
    end

    # The report outcome for the fleet view: the same describe() wording with
    # an explicit unknown whenever the status evidence itself is unreadable,
    # so a fleet row never turns malformed evidence into a positive claim.
    def describe_for_fleet(name, fields)
      describe(read_status(path(name, fields.fetch('spawn_gen'))), name, fields)
    rescue Error, SystemCallError
      'unknown (unreadable status evidence)'
    end

    def read_status(file)
      File.open(file, File::RDONLY | File::NOFOLLOW) do |handle|
        verify_private_file!(handle)
        parse_events(handle.read(MAX_BYTES + 1) || '')
      end
    end

    def verify_private_file!(handle)
      stat = handle.stat
      return if stat.file? && stat.uid == Process.euid && stat.mode.nobits?(0o077)

      raise Error, 'status file is not private and regular'
    end

    def parse_events(bytes)
      lines = valid_status_text(bytes).lines
      events = validated_events(lines)
      gate = events.any? { |event| %w[blocked needs-decision failed].include?(event.kind) }
      Status.new(last: lines.last&.delete_suffix("\n"), open_gate: gate, events: events)
    end

    def validated_events(lines)
      position = 0
      lines.map.with_index(1) do |line, sequence|
        position += line.bytesize
        content = line.delete_suffix("\n")
        raise Error, 'status file contains an invalid event' unless content.match?(EVENT)

        Event.new(sequence: sequence, kind: content.split(' ', 2).first, end_offset: position)
      end
    end

    def valid_status_text(bytes)
      raise Error, 'status file is oversized' if bytes.bytesize > MAX_BYTES

      text = bytes.dup.force_encoding(Encoding::UTF_8)
      raise Error, 'status file is not UTF-8' unless text.valid_encoding?
      raise Error, 'status file has no final newline' unless text.empty? || text.end_with?("\n")

      text
    end
  end
end

require_relative 'result/git_gate'
