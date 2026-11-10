# frozen_string_literal: true

module Riddim
  module Schedules
    # Legacy dev:ino is only automatically upgraded with an exact same-boot
    # match. Reboot recovery requires explicit human attestation, not inode trust.
    module IdentityMigration
      KEYS = %w[home watcher_lock store_lock].freeze
      AUDIT = '.scheduled-prompts.identity-migration.json'

      module_function

      def verify_watcher!(watcher, migrate:)
        Store.verify_lock!(watcher)
        return unless migrate
        return if watcher.flock(File::LOCK_EX | File::LOCK_NB)

        raise Error, 'cannot migrate identities while the watcher lock is held; stop the running watcher first'
      end

      def normalize_filesystem(value)
        raise SourceChanged, '--filesystem must contain 1..16 hexadecimal digits' unless
          value.is_a?(String) && value.match?(/\A[0-9a-fA-F]{1,16}\z/)

        value.downcase.rjust(16, '0')
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def convert!(document, bindings, legacy, approval)
        filesystem = normalize_filesystem(approval['filesystem']) if approval
        old = document.slice(*KEYS)
        return if !approval && old.values.none? { |value| value.is_a?(String) && value.match?(/\A\d+:\d+\z/) }

        valid = KEYS.all? { |key| old[key].is_a?(String) && old[key].match?(/\A\d+:\d+\z/) }
        valid &&= if approval
                    approval.slice(*KEYS) == old && KEYS.all? do |key|
                      old[key].split(':').last == bindings.fetch(key).split(':').last &&
                        bindings.fetch(key).split(':')[1] == filesystem
                    end
                  else
                    old == legacy
                  end
        unless valid
          raise SourceChanged, 'scheduled prompt source ownership changed; legacy device mismatch requires explicit ' \
                               'human-verified schedule migrate-identities (see CLI reference); never trust inode alone'
        end

        document.merge!(bindings)
        { 'old' => old, 'new' => bindings }
      end

      # Persist the attestation before changing the document. Identical retries
      # after interruption are safe; conflicting audit evidence must not be lost.
      # rubocop:disable-next Metrics/MethodLength
      def record!(base, audit)
        path = File.join(base, AUDIT)
        content = JSON.generate(audit)
        begin
          File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
            file.write(content)
            file.fsync
          end
        rescue Errno::EEXIST
          verify_record!(path, content)
        end
        File.open(base, File::RDONLY, &:fsync)
      end

      def verify_record!(path, content)
        File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
          Result.verify_private_file!(file)
          raise Error, 'conflicting identity migration audit' unless
            file.stat.nlink == 1 && file.read(content.bytesize + 1) == content
        end
      end
    end
  end
end
