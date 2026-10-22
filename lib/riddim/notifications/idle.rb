# frozen_string_literal: true

module Riddim
  module Notifications
    # Firstmate's stable nonterminal-idle attention, reduced to verified Pi
    # native idle plus three unchanged captures. This is never completion.
    module Idle
      SAMPLE_SECONDS = 5
      LAUNCH_GRACE_SECONDS = 30
      STABLE_SAMPLES = 3
      FIELDS = %w[first_seen hash last_sample record samples].freeze

      module_function

      def path(name, generation)
        File.join(Notifications.directory, ".idle-#{name}-#{generation}")
      end

      def read(name, generation, digest)
        file = path(name, generation)
        return { 'record' => digest, 'first_seen' => nil, 'last_sample' => nil, 'hash' => nil, 'samples' => 0 } unless
          File.exist?(file) || File.symlink?(file)

        row = JSON.parse(Notifications.private_read(file))
        raise Error, "invalid idle observation at #{file}" unless valid?(row, digest)

        row
      rescue JSON::ParserError => e
        raise Error, "invalid idle observation at #{file}: #{e.message}"
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def valid?(row, digest)
        row.is_a?(Hash) && row.keys.sort == FIELDS && row['record'] == digest &&
          %w[first_seen last_sample].all? do |field|
            row[field].nil? || (row[field].is_a?(Numeric) && row[field].finite? && row[field] >= 0)
          end && row['samples'].is_a?(Integer) && row['samples'].between?(0, STABLE_SAMPLES) &&
          ((row['samples'].zero? && row['hash'].nil?) ||
            (row['samples'].positive? && row['hash'].is_a?(String) && row['hash'].match?(/\A[0-9a-f]{64}\z/)))
      end

      # Prepare only. The caller rechecks ownership under the name lock before
      # committing this candidate or its attention row.
      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def sample(name, snapshot, bytes, state, status)
        endpoint, generation = snapshot
        row = read(name, generation, Digest::SHA256.hexdigest(bytes))
        now = Time.now.to_f
        row.merge!('first_seen' => nil, 'hash' => nil, 'samples' => 0) if row['last_sample'] && now < row['last_sample']
        row['first_seen'] ||= now if state == :alive
        hash = pane_hash(endpoint) if state == :alive && %w[idle done blocked].include?(status)
        gap = row['last_sample'] && (now - row['last_sample'])
        if hash && hash == row['hash'] && gap&.between?(0, SAMPLE_SECONDS * 2)
          return row if gap < SAMPLE_SECONDS

          row['samples'] = [row['samples'] + 1, STABLE_SAMPLES].min
        else
          row['hash'] = hash
          row['samples'] = hash ? 1 : 0
        end
        row['last_sample'] = now
        row
      end

      def pane_hash(endpoint)
        text = Herdr.pane_tail(session: endpoint.session, pane_id: endpoint.pane_id, lines: 40)
        Digest::SHA256.hexdigest(text) unless text.strip.empty?
      rescue Herdr::CommandFailed, SystemCallError
        nil
      end

      def ready?(row)
        row['samples'] >= STABLE_SAMPLES && row['first_seen'] &&
          row['last_sample'] - row['first_seen'] >= LAUNCH_GRACE_SECONDS
      end

      def commit(name, generation, row)
        Notifications.replace(path(name, generation), "#{JSON.generate(row)}\n")
      end
    end
  end
end
