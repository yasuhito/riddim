# frozen_string_literal: true

require_relative '../schedules'

module Riddim
  module Schedules
    # A small argument grammar, intentionally without abbreviated options.
    module CLI
      class Usage < ArgumentError; end

      module_function

      # rubocop:disable-next Metrics/MethodLength, Metrics/CyclomaticComplexity
      def run(arguments)
        Schedules.operator!
        verb, *args = arguments
        case verb
        when 'create' then create(args)
        when 'list' then list(args)
        when 'migrate-identities' then migrate_identities(args)
        when 'cancel' then cancel(args)
        when 'scan' then Schedules.scan(session: options(args, %w[session], %w[session]).fetch('session'))
        when 'ack' then occurrence(args, acknowledge: true)
        when 'offer' then occurrence(args, acknowledge: false)
        else raise Usage, usage
        end
      end

      def migrate_identities(args)
        keys = %w[filesystem home watcher-lock store-lock]
        approval = options(args, keys, keys).transform_keys { |key| key.tr('-', '_') }
        Store.transaction(migrate: approval) { { status: 'identities migrated', audit: IdentityMigration::AUDIT } }
      end

      def usage
        'Usage: riddim schedule create --session <Pi-ID> --prompt-file <path> [--at <offset-datetime>] ' \
          '[--every <Ns|Nm|Nh|Nd>] | list | cancel <schedule-id> | scan --session <Pi-ID> | ' \
          'ack <presented-occurrence-id> --session <Pi-ID> | migrate-identities ' \
          '--filesystem <fsid> --home <old-dev:ino> --watcher-lock <old-dev:ino> --store-lock <old-dev:ino>'
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def options(args, allowed, required)
        raise Usage, usage unless args.size.even?

        parsed = {}
        args.each_slice(2) do |flag, value|
          key = flag.delete_prefix('--')
          raise Usage, usage unless flag.start_with?('--') && allowed.include?(key) && !parsed.key?(key) && value

          parsed[key] = value
        end
        raise Usage, usage unless required.all? { |key| parsed.key?(key) }

        parsed
      end

      def create(args)
        parsed = options(args, %w[session prompt-file at every], %w[session prompt-file])
        Schedules.create(session: parsed['session'], prompt_file: parsed['prompt-file'],
                         at: parsed['at'], every: parsed['every'])
      end

      def list(args)
        raise Usage, usage unless args.empty?

        Schedules.list
      end

      def cancel(args)
        raise Usage, usage unless args.size == 1

        Schedules.cancel(args.first)
      end

      def occurrence(args, acknowledge:)
        id, *rest = args
        keys = acknowledge ? %w[session] : %w[session home lock]
        parsed = options(rest, keys, keys)
        return Schedules.acknowledge(id, session: parsed['session']) if acknowledge

        Schedules.offer(id, session: parsed['session'], expected: parsed.values_at('home', 'lock'))
      end
    end
  end
end
