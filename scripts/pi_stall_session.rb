# frozen_string_literal: true

require 'json'
require 'time'

module PiStallLab
  # Classifies recorded empty aborted replies without exposing message contents.
  module Trace
    EVENTS = %w[session_start agent_start turn_start request_prepared response_headers first_update
                turn_end agent_settled].freeze

    module_function

    def no_visible_content?(content)
      content.is_a?(Array) && content.all? { |part| part.is_a?(Hash) && part['text'].to_s.empty? }
    end

    def empty_abort?(row)
      return false unless row['type'] == 'message' && row['message'].is_a?(Hash)

      message = row['message']
      message['role'] == 'assistant' && message['stopReason'] == 'aborted' && no_visible_content?(message['content'])
    end

    def stalled_intervals(rows)
      messages = rows.select { |row| row['type'] == 'message' && row['message'].is_a?(Hash) }
      messages.each_cons(2).filter_map do |previous, current|
        next unless empty_abort?(current)

        seconds = Time.iso8601(current.fetch('timestamp')) - Time.iso8601(previous.fetch('timestamp'))
        [previous.fetch('message').fetch('role'), seconds.round]
      end
    end

    def parse_row(line, index)
      JSON.parse(line)
    rescue JSON::ParserError
      raise ArgumentError, "invalid session JSONL at line #{index + 1}"
    end

    def observe(file)
      File.foreach(file).each_with_index do |line, index|
        row = parse_row(line, index)
        next unless EVENTS.include?(row['event']) && row['request'].is_a?(Integer)

        at = Time.iso8601(row.fetch('at')).utc.iso8601
        puts "#{at} request=#{row['request']} #{row['event']}"
      end
    end

    def replay(file)
      rows = File.foreach(file).each_with_index.map { |line, index| parse_row(line, index) }
      intervals = stalled_intervals(rows)
      intervals.each { |role, seconds| puts "empty aborted response after #{role}: #{seconds}s" }
      puts 'No empty aborted response recorded' if intervals.empty?
    end
  end
end
