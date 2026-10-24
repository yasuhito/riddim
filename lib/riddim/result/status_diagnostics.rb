# frozen_string_literal: true

require 'shellwords'

module Riddim
  # Read-only guidance from the existing generation-local status fold.
  module Result
    DECISION_OUTPUT_BYTES = 4000

    module_function

    def describe(status, name, fields)
      event = status.last
      return 'unreported' unless event

      outcome = if event.start_with?('done ')
                  ready = !status.open_gate && ready?(name, fields)
                  ready ? "ready: #{event}" : "reported (not ready): #{event}"
                else
                  "reported: #{event}"
                end
      diagnostics = status_diagnostics(status, name)
      diagnostics.empty? ? outcome : "#{outcome} [not ready: #{diagnostics}]"
    end

    # The report outcome for the fleet view: the same describe() wording with
    # an explicit unknown whenever the status evidence itself is unreadable,
    # so a fleet row never turns malformed evidence into a positive claim.
    def describe_for_fleet(name, fields)
      describe(read_status(path(name, fields.fetch('spawn_gen'))), name, fields)
    rescue Error, SystemCallError
      'unknown (unreadable status evidence)'
    end

    def status_diagnostics(status, name)
      reasons = []
      reasons << decision_guidance(status.open_keys, name) unless status.open_keys.empty?
      if status.events.any? { |event| event.kind == 'failed' }
        reasons << 'failed history remains a gate; investigate the failure (key resolution cannot clear it)'
      end
      unless status.last&.start_with?('done ')
        reasons << 'no current done report; obtain a fresh done report after addressing gates'
      end
      reasons << 'Git checks, review and exact-SHA human approval still required' unless reasons.empty?
      reasons.join('; ')
    end

    def decision_guidance(keys, name)
      name = Ownership.validated_name(name)
      items = keys.map { |key, kind| decision_item(name, key, kind) }
      used = 0
      shown = items.take_while { |item| (used += item.bytesize + 2) <= DECISION_OUTPUT_BYTES }
      omitted = keys.size - shown.size
      shown << "#{omitted} more open decisions omitted (byte cap)" if omitted.positive?
      "open decisions: #{shown.join(', ')}; replace <answer> with a warranted answer for each key, " \
        'then obtain a fresh done report'
    end

    def decision_item(name, key, kind)
      command = Shellwords.join(['riddim', 'send', name, '--resolve-key', key])
      "#{key} (#{kind}): #{command} '<answer>'"
    end
  end
end
