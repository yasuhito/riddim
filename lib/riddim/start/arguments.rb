# frozen_string_literal: true

module Riddim
  module Start
    # Strict, order-independent start flags. No abbreviation or last-value wins.
    module Arguments
      USAGE = 'Usage: riddim start <name> [--worktree [--task-file <path> [--mode local-only]]] ' \
              '[--model <model-id>] [--effort <effort>]'
      VALUE_FLAGS = %w[--task-file --mode --model --effort].freeze

      class Error < StandardError; end

      module_function

      def parse(arguments)
        values = {}
        remaining = arguments.dup
        until remaining.empty?
          flag, separator, value = remaining.shift.partition('=')
          raise Error, USAGE if values.key?(flag)

          values[flag] = flag_value(flag, separator, value, remaining)
        end
        validate_combinations(values)
        values
      end

      def flag_value(flag, separator, value, remaining)
        return true if flag == '--worktree' && separator.empty?

        raise Error, USAGE unless VALUE_FLAGS.include?(flag)

        value = remaining.shift if separator.empty?
        raise Error, "riddim: #{flag} requires a nonempty value without control characters" unless valid_value?(value)

        value
      end

      def valid_value?(value)
        value && !value.empty? && !value.start_with?('--') && value.valid_encoding? && !value.match?(/[[:cntrl:]]/)
      end

      def validate_combinations(values)
        raise Error, USAGE if values.key?('--task-file') && !values['--worktree']
        return unless values.key?('--mode')
        return if values['--mode'] == 'local-only' && values['--worktree'] && values['--task-file']

        raise Error, USAGE
      end
    end
  end
end
