# frozen_string_literal: true

require 'json'
require 'open3'

module Riddim
  # Reads and validates Herdr's concrete command-line state representation.
  module Herdr
    AGENT_STATUSES = %w[blocked done idle unknown working].freeze

    # Preserves a failed Herdr process's observable result for the caller.
    class CommandFailed < StandardError
      attr_reader :stdout, :stderr, :exitstatus

      def initialize(stdout, stderr, exitstatus)
        super("Herdr exited with status #{exitstatus}")
        @stdout = stdout
        @stderr = stderr
        @exitstatus = exitstatus
      end
    end

    class InvalidResponse < StandardError; end

    module_function

    def agent(target)
      stdout, stderr, status = Open3.capture3('herdr', 'agent', 'get', target)
      raise CommandFailed.new(stdout, stderr, status.exitstatus) unless status.success?

      parse_agent(stdout)
    end

    def parse_agent(json)
      document = JSON.parse(json)
      result = document['result'] if document.is_a?(Hash)
      agent = result['agent'] if result.is_a?(Hash)
      status = agent['agent_status'] if agent.is_a?(Hash)
      return agent if AGENT_STATUSES.include?(status)

      raise InvalidResponse, 'expected result.agent.agent_status to be idle, working, blocked, done, or unknown'
    rescue JSON::ParserError
      raise InvalidResponse, 'malformed JSON'
    end
  end
end
