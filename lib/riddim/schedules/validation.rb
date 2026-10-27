# frozen_string_literal: true

require 'time'

module Riddim
  module Schedules
    # Deliberately bounded syntax: no cron, local-time guessing or calendar engine.
    # rubocop:disable-next Metrics/ModuleLength
    module Validation
      SESSION = /\A[A-Za-z0-9][A-Za-z0-9_-]{0,127}\z/
      SCHEDULE = /\A[0-9a-f]{32}\z/
      OCCURRENCE = /\Ascheduled\.([0-9a-f]{32})\.([1-9]\d{0,9})\z/
      MAX_TIME = 4_102_444_800 # 2100-01-01T00:00:00Z
      MAX_INTERVAL = 31_536_000
      MAX_PROMPT = 16_384
      MAX_SCHEDULES = 128
      MAX_SEQUENCE = 1_000_000_000

      module_function

      def session!(value)
        return value if value.is_a?(String) && value.match?(SESSION)

        raise Error, 'explicit Pi session ID required; verify your own ID with Pi /session or metadata, never guess'
      end

      def time!(value)
        raise Error, 'time must be whole seconds between 1970-01-01 and 2100-01-01 UTC' unless
          value.is_a?(Integer) && (0..MAX_TIME).cover?(value)

        value
      end

      def datetime(value)
        raise Error, 'use YYYY-MM-DDTHH:MM:SS+HH:MM (explicit numeric UTC offset required)' unless
          value.is_a?(String) && value.match?(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d\d:\d\d\z/)

        parsed = Time.iso8601(value)
        raise Error, 'invalid datetime or UTC offset' unless
          parsed.strftime('%Y-%m-%dT%H:%M:%S%:z') == value && parsed.utc_offset.abs <= 50_400

        time!(parsed.to_i)
      rescue ArgumentError
        raise Error, 'invalid datetime'
      end

      def interval(value)
        match = /\A([1-9]\d{0,7})(s|m|h|d)\z/.match(value.to_s)
        raise Error, 'interval must be a positive integer followed by s, m, h or d (maximum 365d)' unless match

        interval!(match[1].to_i * { 's' => 1, 'm' => 60, 'h' => 3600, 'd' => 86_400 }.fetch(match[2]))
      end

      def interval!(seconds)
        raise Error, 'interval must be between 1s and 365d' unless
          seconds.is_a?(Integer) && (1..MAX_INTERVAL).cover?(seconds)

        seconds
      end

      def prompt!(value)
        raise Error, 'prompt must be nonblank UTF-8, without NUL, at most 16384 bytes' unless
          value.is_a?(String) && value.encoding != Encoding::ASCII_8BIT && value.valid_encoding? &&
          value.bytesize <= MAX_PROMPT && !value.include?("\0") && !value.strip.empty?

        value
      end

      def keys!(value, keys)
        raise Error, 'corrupt scheduled prompt fields' unless value.is_a?(Hash) && value.keys.sort == keys.sort
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def document!(value, bindings)
        keys!(value, %w[schema home watcher_lock store_lock schedules])
        raise Error, 'scheduled prompt source ownership changed or schema is corrupt' unless
          value['schema'] == Store::SCHEMA && bindings.all? { |key, binding| value[key] == binding }

        rows = value['schedules']
        raise Error, 'corrupt scheduled prompt inventory' unless rows.is_a?(Array) && rows.size <= MAX_SCHEDULES

        rows.each { |row| schedule!(row) }
        raise Error, 'duplicate schedule identity' unless rows.map { |row| row['id'] }.uniq.size == rows.size
      end

      # rubocop:disable-next Metrics/AbcSize
      def schedule!(row)
        keys!(row, %w[id session prompt at every next_at cancelled sequence handled_through occurrence])
        raise Error, 'invalid schedule identity' unless row['id'].is_a?(String) && row['id'].match?(SCHEDULE)

        session!(row['session'])
        prompt!(row['prompt'])
        time!(row['at'])
        interval!(row['every']) unless row['every'].nil?
        time!(row['next_at']) unless row['next_at'].nil?
        lifecycle!(row)
        cadence!(row)
        occurrence!(row)
      end

      def lifecycle!(row)
        sequence = row['sequence']
        raise Error, 'invalid schedule lifecycle' unless
          [true, false].include?(row['cancelled']) && sequence.is_a?(Integer) && (0..MAX_SEQUENCE).cover?(sequence) &&
          row['handled_through'].is_a?(Integer) && (0..sequence).cover?(row['handled_through'])
      end

      def on_cadence?(row, time)
        time >= row['at'] && (row['every'] ? ((time - row['at']) % row['every']).zero? : time == row['at'])
      end

      # rubocop:disable-next Metrics/CyclomaticComplexity
      def cadence!(row)
        next_at = row['next_at']
        raise Error, 'invalid schedule cadence' if next_at && !on_cadence?(row, next_at)
        raise Error, 'cancelled schedule has a future occurrence' if row['cancelled'] && next_at
        raise Error, 'active recurring schedule has no next occurrence' if
          row['every'] && !row['cancelled'] && next_at.nil?
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def occurrence!(row)
        value = row['occurrence']
        if value.nil?
          raise Error, 'missing scheduled occurrence' unless row['sequence'].zero? && row['handled_through'].zero? &&
                                                             (row['cancelled'] || row['next_at'] == row['at'])

          return
        end
        keys!(value, %w[id due_at status offered])
        time!(value['due_at'])
        raise Error, 'corrupt scheduled occurrence' unless
          row['sequence'].positive? && value['id'] == "scheduled.#{row['id']}.#{row['sequence']}" &&
          %w[pending handled cancelled].include?(value['status']) && [true, false].include?(value['offered']) &&
          on_cadence?(row, value['due_at'])

        receipt!(row, value)
        raise Error, 'invalid scheduled next occurrence' if
          (!row['every'] && row['next_at']) || (row['next_at'] && row['next_at'] <= value['due_at'])
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def receipt!(row, value)
        handled = value['status'] == 'handled'
        expected = handled ? row['sequence'] : row['sequence'] - 1
        raise Error, 'inconsistent scheduled handling receipt' unless
          row['handled_through'] == expected && (!handled || value['offered'])
        raise Error, 'inconsistent scheduled cancellation' if
          (value['status'] == 'cancelled' && !row['cancelled']) || (row['cancelled'] && value['status'] == 'pending')
      end
    end
  end
end
