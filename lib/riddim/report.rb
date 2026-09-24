# frozen_string_literal: true

require_relative 'result'

module Riddim
  # Serialize local-only worker reports with the operator's landing action.
  # A status append without this shared per-name lock is outside that contract.
  module Report
    class Refused < Result::Error; end

    module_function

    def run(name, generation, event)
      Result.task_record(name) # Refuse missing/non-local records before creating a lock.
      Ownership.with_lock(name) { append_locked(name, generation, event) }
      "reported #{name} for #{generation}"
    end

    def append_locked(name, generation, event)
      snapshot, fields, bytes = Result.task_record(name)
      verify_target!(fields, snapshot.last, generation, event)
      File.open(Result.path(name, generation), File::RDWR | File::APPEND | File::NOFOLLOW) do |file|
        append_event!(file, name, snapshot, bytes, event)
      end
    rescue SystemCallError => e
      raise Refused, "worker status could not be written: #{e.message}"
    end

    def verify_target!(fields, current, requested, event)
      unless fields['status_protocol'] == Result::STATUS_PROTOCOL
        raise Refused, 'worker does not use the locked report protocol'
      end
      raise Refused, 'report belongs to another worker generation' unless current == requested
      raise Refused, 'invalid worker status event' unless event.match?(Result::EVENT)
    end

    def append_event!(file, name, snapshot, bytes, event)
      Result.verify_private_file!(file)
      file.rewind
      contents = file.read(Result::MAX_BYTES + 1) || ''
      Result.parse_events(contents)
      raise Refused, 'status file is oversized' if contents.bytesize + event.bytesize + 1 > Result::MAX_BYTES

      verify_owner!(name, snapshot, bytes)
      file.write("#{event}\n")
      file.flush
      file.fsync
      verify_owner!(name, snapshot, bytes)
    end

    def verify_owner!(name, snapshot, bytes)
      return if Ownership::Endpoint.unchanged?(name, snapshot) &&
                Ownership::Endpoint.read_bytes(Ownership.record_path(name)) == bytes

      raise Refused, 'ownership changed during worker report'
    end
  end
end
