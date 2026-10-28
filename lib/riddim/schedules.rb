# frozen_string_literal: true

require_relative 'actor'
require_relative 'schedules/store'
require_relative 'schedules/validation'

module Riddim
  # Human-configured prompts, never Worker reports, readiness or approval.
  # rubocop:disable-next Metrics/ModuleLength
  module Schedules
    class Error < Ownership::Error; end

    # Shared home/watcher identity is authoritative for ordinary reports too.
    class SourceChanged < Error; end

    module_function

    def operator!
      return if ENV.fetch(Actor::VARIABLE, '').empty?

      raise Error, 'scheduled supervisor prompts are operator-only; marked workers and unknown actors cannot use them'
    end

    def present?
      path = File.join(Ownership.state_dir, Store::FILE)
      lock = File.join(Ownership.state_dir, Store::LOCK)
      File.exist?(path) || File.symlink?(path) || File.exist?(lock) || File.symlink?(lock)
    end

    def read_prompt(path)
      File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
        raise Error, 'prompt file must be a regular file' unless file.stat.file?

        Validation.prompt!((file.read(Validation::MAX_PROMPT + 1) || String.new).force_encoding(Encoding::UTF_8))
      end
    end

    # rubocop:disable-next Metrics/MethodLength
    def create(session:, prompt_file:, at: nil, every: nil, now: Time.now.to_i)
      operator!
      Validation.session!(session)
      interval = every && Validation.interval(every)
      raise Error, '--at is required for a one-shot prompt' unless at || interval

      first = at ? Validation.datetime(at) : Validation.time!(now + interval)
      prompt = read_prompt(prompt_file)
      Store.transaction(create: true) do |rows|
        raise Error, 'scheduled prompt inventory limit reached (128 schedules, including completed/cancelled)' if
          rows.size >= Validation::MAX_SCHEDULES

        row = { 'id' => SecureRandom.hex(16), 'session' => session, 'prompt' => prompt, 'at' => first,
                'every' => interval, 'next_at' => first, 'cancelled' => false, 'sequence' => 0,
                'handled_through' => 0, 'occurrence' => nil }
        rows << row
        row
      end
    end

    def list
      operator!
      return [] unless present?

      Store.transaction { |rows| rows }
    end

    def cancel(id)
      operator!
      Store.transaction do |rows|
        row = find_schedule(rows, id)
        row['cancelled'] = true
        row['next_at'] = nil
        occurrence = row['occurrence']
        occurrence['status'] = 'cancelled' if occurrence && occurrence['status'] == 'pending'
        row
      end
    end

    # Only the existing watcher calls this. A missing/unknown session may
    # materialize due work but receives no prompt IDs. Other recipients stay
    # pending. Cadence advances even while one stable occurrence is outstanding.
    # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/MethodLength
    def pending(session:, now: Time.now.to_i)
      operator!
      Validation.session!(session) unless session.nil?
      return [] unless present?

      Validation.time!(now)
      Store.transaction do |rows|
        rows.each { |row| reconcile(row, now) }
        rows.filter_map do |row|
          value = row['occurrence']
          value['id'] if row['session'] == session && value && value['status'] == 'pending'
        end
      end
    end

    # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def reconcile(row, now)
      due = row['next_at']
      return unless due && due <= now

      value = row['occurrence']
      unless value && value['status'] == 'pending'
        raise Error, 'scheduled occurrence sequence exhausted' if row['sequence'] >= Validation::MAX_SEQUENCE

        row['sequence'] += 1
        row['occurrence'] = { 'id' => "scheduled.#{row['id']}.#{row['sequence']}", 'due_at' => due,
                              'status' => 'pending', 'offered' => false }
      end
      interval = row['every']
      next_at = interval && (due + ((((now - due) / interval) + 1) * interval))
      if next_at && next_at > Validation::MAX_TIME
        raise Error, 'scheduled cadence exceeds 2100-01-01; cancel the schedule'
      end

      row['next_at'] = next_at
    end

    # Durable offer is the cancellation linearization point, not a delivery
    # receipt. Cancel before this prevents dispatch. Cancel after it cannot
    # retract an in-flight/queued/already-delivered follow-up. ACK stays explicit.
    def offer(id, session:, expected: nil)
      operator!
      Validation.session!(session)
      Store.transaction(expected: expected) do |rows|
        row, value = find_occurrence(rows, id, session)
        next unless value && value['status'] == 'pending' && !row['cancelled']

        value['offered'] = true
        { kind: 'scheduled-prompt', id: id, session: session, prompt: row['prompt'], due_at: value['due_at'] }
      end
    end

    def scan(session:)
      pending(session: session).filter_map { |id| offer(id, session: session) }
    end

    # rubocop:disable-next Metrics/MethodLength
    def acknowledge(id, session:)
      operator!
      Validation.session!(session)
      Store.transaction do |rows|
        row, value = find_occurrence(rows, id, session)
        sequence = Validation::OCCURRENCE.match(id)[2].to_i
        next({ id: id, status: 'handled' }) if sequence <= row['handled_through']
        raise Error, 'scheduled occurrence was not presented to this session' unless value && value['offered']

        value['status'] = 'handled'
        row['handled_through'] = sequence
        { id: id, status: 'handled' }
      end
    end

    def find_schedule(rows, id)
      raise Error, 'invalid schedule ID' unless id.is_a?(String) && id.match?(Validation::SCHEDULE)

      rows.find { |row| row['id'] == id } || raise(Error, 'unknown schedule ID')
    end

    def find_occurrence(rows, id, session)
      match = id.is_a?(String) && Validation::OCCURRENCE.match(id)
      raise Error, 'invalid scheduled occurrence ID' unless match

      row = find_schedule(rows, match[1])
      raise Error, 'scheduled prompt belongs to a different Pi session; use the original authorized session' unless
        row['session'] == session
      raise Error, 'unknown scheduled occurrence' if match[2].to_i > row['sequence']

      value = row['occurrence']
      [row, value && value['id'] == id ? value : nil]
    end
  end
end
