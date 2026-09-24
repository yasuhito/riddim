# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'
require_relative 'result'

module Riddim
  # A read-only fleet overview for one selected state directory: Firstmate's
  # fleet-snapshot row shape, reduced to what Riddim owns. Each row pairs a
  # validated ownership record with separately attributed evidence - this
  # generation's read-only local-only report claim and the exact recorded
  # pane's Pi process view. It is not Firstmate's fleet state: no backlog,
  # registered secondmates, remote summaries, PRs, notifications, or inferred
  # current crew state, and no ownership, status, or Git writes. A record
  # removed during enumeration is absent; any still-present but invalid record
  # fails the whole read, like List.
  module Fleet
    SCHEMA = 'riddim.fleet.v1'

    class Error < Ownership::Error; end

    module_function

    # The primary machine-readable shape. The human view renders these same
    # facts and never parses state files again.
    def snapshot
      { schema: SCHEMA, state_dir: Ownership.state_dir, records: rows }
    end

    # Firstmate's fleet-view shape: a pure renderer over the snapshot, one
    # table line per record carrying exactly the JSON row's facts.
    def render(snapshot)
      header = ['# Fleet View', '', "Schema: #{snapshot.fetch(:schema)}",
                "State: #{snapshot.fetch(:state_dir)}", '']
      body = render_records(snapshot.fetch(:records))
      "#{(header + body).join("\n")}\n"
    end

    def render_records(records)
      return ['No records: no recorded workers in this state directory.'] if records.empty?

      rows = [['| Name | Session | Pane | Task mode | Report | Pi process |',
               '| --- | --- | --- | --- | --- | --- |']]
      rows.concat(records.map { |record| table_row(record) })
      rows.flatten
    end

    def table_row(record)
      cells = [record.fetch(:name), record.fetch(:session), record.fetch(:pane_id),
               record.fetch(:task_mode, '-'), record.fetch(:report, '-'),
               record.fetch(:pi_process, '-')]
      "| #{cells.join(' | ')} |"
    end

    def rows
      List.record_names.map { |name| row(name) }
    end

    # One row: the validated record identity plus mutable evidence that is
    # discarded whenever ownership changes during the observations.
    def row(name)
      record = captured_record(name)
      mutable = observe_mutables(name, record_fields(name))
      record.merge!(mutable) if unchanged?(name, record.delete(:bytes))
      record
    end

    # Captures one record's identity, task mode, and exact bytes together, so
    # every later observation belongs to one selected generation.
    def captured_record(name)
      endpoint, generation = Ownership::Endpoint.resolve_snapshot(name)
      bytes = Ownership::Endpoint.read_bytes(Ownership.record_path(name))
      fields = Ownership.parse(bytes)
      raise Error, 'fleet record changed while reading' unless fields['spawn_gen'] == generation

      { name: name, session: endpoint.session, pane_id: endpoint.pane_id,
        task_mode: fields['task_mode'], bytes: bytes }.compact
    rescue Ownership::Endpoint::Refused, Ownership::InvalidRecord
      # Like Firstmate's snapshot, a record removed during enumeration is
      # absent. Any still-present but invalid record fails the whole read.
      raise if Ownership.record_present?(Ownership.record_path(name))

      nil
    end

    def record_fields(name)
      Ownership.parse(Ownership::Endpoint.read_bytes(Ownership.record_path(name)))
    end

    # Mutable observations for one captured record, each attributed
    # separately. A report outcome is a claim, not human approval; the Pi
    # process view is an exact-pane observation, not agent registration.
    def observe_mutables(name, fields)
      mutable = {}
      mutable[:report] = Result.describe_for_fleet(name, fields) if fields['task_mode'] == 'local-only'
      mutable[:pi_process] = pi_process_verdict(name)
      mutable
    end

    # The exact recorded pane's Pi process verdict, or "unknown" whenever any
    # observation is unreadable: an unknown never becomes a positive claim.
    def pi_process_verdict(name)
      endpoint = Ownership::Endpoint.resolve(name)
      Herdr.pi_process_state(endpoint.pane_id, session: endpoint.session).to_s
    rescue Herdr::InvalidResponse, Ownership::Error
      'unknown'
    end

    # Mutable evidence is retained only while the captured record still
    # identifies this spawn, so an old worker's pane is never attributed to a
    # replacement. The row keeps its captured identity alone.
    def unchanged?(name, bytes)
      Ownership::Endpoint.unchanged?(name, resolve_current(name)) &&
        Ownership::Endpoint.read_bytes(Ownership.record_path(name)) == bytes
    end

    def resolve_current(name)
      Ownership::Endpoint.resolve_snapshot(name)
    rescue Ownership::Endpoint::Refused
      nil
    end
  end
end
