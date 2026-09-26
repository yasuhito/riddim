# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'
require_relative 'instruction_inbox'
require_relative 'report'

module Riddim
  # The ownership-safe send corridor. The unlocked read refuses missing
  # ownership without creating a lock file; the locked re-read is the routing
  # authority. Local-only text is stored before best-effort notification;
  # other input remains a direct prompt under the same lifecycle lock.
  module Send
    module_function

    def run(name, message, resolve_key: nil, endpoint_records: Ownership::Endpoint, locks: Ownership, herdr: Herdr) # rubocop:disable Metrics/ParameterLists
      endpoint_records.resolve(name)
      locks.with_lock(name, inherit_on_exec: true) { route_locked(name, message, endpoint_records, herdr, resolve_key) }
    end

    def route_locked(name, message, endpoint_records, herdr, resolve_key = nil)
      endpoint, generation = endpoint_records.resolve_snapshot(name)
      fields = Ownership.parse(endpoint_records.read_bytes(Ownership.record_path(name)))
      if inbox_target?(fields, message) || (resolve_key && fields['task_mode'] == 'local-only')
        verify_instruction_owner!(name, endpoint, generation, fields)
        verify_open_key!(name, generation, resolve_key) if resolve_key
        return deliver_instruction(name, generation, endpoint, message, herdr, resolve_key)
      end
      raise InstructionInbox::Error, 'keyed answers require a local-only instruction' if resolve_key

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

    def verify_open_key!(name, generation, key)
      status = Result.read_status(Result.path(name, generation))
      raise InstructionInbox::Error, "decision key #{key} is not open" unless status.open_keys.key?(key)
    end

    def close_answer!(name, generation, key, message)
      snapshot, _fields, bytes = Result.task_record(name)
      raise InstructionInbox::Error, 'answer generation changed' unless snapshot.last == generation

      event = answer_event(key, message)
      File.open(Result.path(name, generation), File::RDWR | File::APPEND | File::NOFOLLOW) do |file|
        Report.append_event!(file, name, snapshot, bytes, event)
      end
      status = Result.read_status(Result.path(name, generation))
      raise InstructionInbox::Error, 'decision remains open after answer' if status.open_keys.key?(key)
    end

    def answer_event(key, message)
      "resolved [key=#{key}] [at=#{Time.now.to_i}]: answered: #{message.gsub(/[\r\n\x00]/, ' ')[0, 256]}"
    end

    def deliver_instruction(name, generation, endpoint, message, herdr, resolve_key = nil) # rubocop:disable Metrics/ParameterLists
      dir = InstructionInbox.path(name, generation)
      bell = InstructionInbox.notification(dir)
      record = InstructionInbox.enqueue(name, generation, message)
      close_delivered_answer!(name, generation, resolve_key, message, record) if resolve_key
      notify_worker(herdr, endpoint, bell, record)
      puts "instruction stored at #{record} (not a receipt or completion)"
      nil
    end

    def close_delivered_answer!(name, generation, key, message, record)
      close_answer!(name, generation, key, message)
    rescue StandardError => e
      raise InstructionInbox::Error,
            "answer stored at #{record}; do not resend; decision #{key} close unconfirmed " \
            "(may remain open; inspect status and repair): #{e.message}"
    end

    # rubocop:disable-next Metrics/CyclomaticComplexity
    def notify_worker(herdr, endpoint, bell, record)
      state = herdr.agent_state(endpoint.pane_id, session: endpoint.session)
      composer = herdr.composer_state(endpoint.pane_id, session: endpoint.session) unless %i[dead
                                                                                             missing].include?(state)
      unless %i[dead missing].include?(state)
        return if composer == :pending && submit_existing_doorbell?(herdr, endpoint, bell)
        return if composer != :pending && herdr.notify?(endpoint.pane_id, bell, session: endpoint.session)
      end

      warn "riddim: notification skipped or unconfirmed; instruction stored at #{record}; do not resend"
    rescue StandardError
      warn "riddim: notification skipped or unconfirmed; instruction stored at #{record}; do not resend"
    end

    # An earlier notification may have been typed but not submitted. Only a
    # positively identified copy of our own doorbell may receive Enter; a
    # different pending draft is never submitted or overwritten.
    def submit_existing_doorbell?(herdr, endpoint, bell)
      pane = endpoint.pane_id
      session = endpoint.session
      return false if herdr.busy_state(pane, session: session) == :busy
      return false unless herdr.composer_holds_line?(pane, bell, session: session)

      herdr.send_key(pane, 'Enter', session: session)
      sleep 0.3
      herdr.send_key(pane, 'Enter', session: session) if herdr.composer_holds_line?(pane, bell, session: session)
      true
    end
  end
end
