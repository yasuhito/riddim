# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'
require_relative 'instruction_inbox'

module Riddim
  # The ownership-safe send corridor. The unlocked read refuses missing
  # ownership without creating a lock file; the locked re-read is the routing
  # authority. Local-only text is stored before best-effort notification;
  # other input remains a direct prompt under the same lifecycle lock.
  module Send
    module_function

    def run(name, message, endpoint_records: Ownership::Endpoint, locks: Ownership, herdr: Herdr)
      endpoint_records.resolve(name)
      locks.with_lock(name, inherit_on_exec: true) { route_locked(name, message, endpoint_records, herdr) }
    end

    def route_locked(name, message, endpoint_records, herdr)
      endpoint, generation = endpoint_records.resolve_snapshot(name)
      fields = Ownership.parse(endpoint_records.read_bytes(Ownership.record_path(name)))
      if inbox_target?(fields, message)
        verify_instruction_owner!(name, endpoint, generation, fields)
        return deliver_instruction(name, generation, endpoint, message, herdr)
      end
      herdr.prompt(endpoint.pane_id, message, session: endpoint.session)
    end

    def verify_instruction_owner!(name, endpoint, generation, fields)
      Ownership::Endpoint.validate(name, Ownership.record_path(name), fields)
      identity = fields.values_at('herdr_session', 'herdr_workspace_id', 'herdr_tab_id', 'herdr_pane_id')
      raise InstructionInbox::Error, 'instruction endpoint changed' unless identity == endpoint.to_a
      raise InstructionInbox::Error, 'instruction ownership changed' if fields['spawn_gen'] != generation
    end

    def inbox_target?(fields, message)
      fields['task_mode'] == 'local-only' && !message.start_with?('/')
    end

    def deliver_instruction(name, generation, endpoint, message, herdr)
      dir = InstructionInbox.path(name, generation)
      bell = InstructionInbox.notification(dir)
      record = InstructionInbox.enqueue(name, generation, message)
      notify_worker(herdr, endpoint, bell, record)
      puts "instruction stored at #{record} (not a receipt or completion)"
      nil
    end

    def notify_worker(herdr, endpoint, bell, record)
      state = herdr.agent_state(endpoint.pane_id, session: endpoint.session)
      composer = herdr.composer_state(endpoint.pane_id, session: endpoint.session) unless %i[dead
                                                                                             missing].include?(state)
      return if !%i[dead missing].include?(state) && composer != :pending &&
                herdr.notify?(endpoint.pane_id, bell, session: endpoint.session)

      warn "riddim: notification skipped or unconfirmed; instruction stored at #{record}; do not resend"
    rescue StandardError
      warn "riddim: notification skipped or unconfirmed; instruction stored at #{record}; do not resend"
    end
  end
end
