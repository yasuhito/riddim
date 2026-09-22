# frozen_string_literal: true

module Riddim
  # The local one-line agent launch profile: "<harness> <model> <effort>".
  class AgentProfile
    FILENAME = 'agent-profile'
    SUPPORTED_HARNESS = 'pi'
    SUPPORTED_EFFORTS = %w[low medium high xhigh max].freeze
    MALFORMED_MESSAGE = 'malformed profile line: expected "<harness> <model> <effort>"'

    class Error < StandardError; end

    attr_reader :harness, :model, :effort

    def initialize(harness:, model:, effort:)
      @harness = harness
      @model = model
      @effort = effort
    end

    def self.load(config_dir:)
      path = File.join(config_dir, FILENAME)
      begin
        text = File.read(path)
      rescue Errno::ENOENT
        raise Error, "missing profile file: #{FILENAME}"
      rescue SystemCallError
        raise Error, "unreadable profile file: #{FILENAME}"
      end

      parse(text)
    end

    def self.parse(text)
      lines = profile_lines(text)
      raise Error, "no profile line in #{FILENAME}" if lines.empty?
      raise Error, "expected one profile line in #{FILENAME}, found #{lines.length}" if lines.length > 1

      tokens = lines.first.split
      raise Error, MALFORMED_MESSAGE unless tokens.length == 3

      harness, model, effort = tokens
      validate_harness(harness)
      validate_model(model)
      validate_effort(effort)

      new(harness: harness, model: model, effort: effort)
    end

    def self.validate_harness(harness)
      return if harness == SUPPORTED_HARNESS

      raise Error, "unsupported harness #{harness.dump}: only #{SUPPORTED_HARNESS.dump} is supported"
    end

    def self.validate_model(model)
      return unless model.match?(/[[:cntrl:]]/)

      raise Error, 'unsupported model: control characters are not allowed'
    end

    def self.validate_effort(effort)
      return if SUPPORTED_EFFORTS.include?(effort)

      raise Error, "unsupported effort #{effort.dump}: expected one of #{SUPPORTED_EFFORTS.join(', ')}"
    end

    def self.profile_lines(text)
      text.lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
    end

    private_class_method :validate_harness, :validate_model, :validate_effort, :profile_lines
  end
end
