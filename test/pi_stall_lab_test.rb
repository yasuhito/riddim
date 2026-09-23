# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../scripts/pi_stall_lab'

class PiStallLabTest < Minitest::Test
  def event(role, timestamp, stop_reason: nil, content: [])
    { 'type' => 'message', 'timestamp' => timestamp,
      'message' => { 'role' => role, 'stopReason' => stop_reason, 'content' => content } }
  end

  def test_reports_only_empty_aborted_turns_and_elapsed_time
    rows = [
      event('toolResult', '2026-09-23T00:00:00Z'),
      event('assistant', '2026-09-23T00:05:24Z', stop_reason: 'aborted'),
      event('user', '2026-09-23T00:06:00Z'),
      event('assistant', '2026-09-23T00:09:07Z', stop_reason: 'aborted'),
      event('user', '2026-09-23T00:10:00Z'),
      event('assistant', '2026-09-23T00:13:00Z', stop_reason: 'stop', content: [{ 'text' => 'OK' }])
    ]

    assert_equal [['toolResult', 324], ['user', 187]], PiStallLab::Trace.stalled_intervals(rows)
  end

  def test_never_prints_message_contents
    Tempfile.create(['pi-session-', '.jsonl']) do |file|
      rows = [event('user', '2026-09-23T00:00:00Z', content: [{ 'text' => 'PRIVATE TASK TEXT' }]),
              event('assistant', '2026-09-23T00:03:07Z', stop_reason: 'aborted')]
      rows.each { |row| file.puts(JSON.generate(row)) }
      file.flush
      output, = capture_io { PiStallLab::Trace.replay(file.path) }

      assert_equal "empty aborted response after user: 187s\n", output
    end
  end

  def test_live_trace_only_displays_known_metadata
    Tempfile.create(['pi-trace-', '.jsonl']) do |file|
      file.puts(JSON.generate('at' => '2026-09-23T00:00:00Z', 'request' => 1,
                              'event' => 'request_prepared', 'payload' => 'SECRET'))
      file.puts(JSON.generate('at' => '2026-09-23T00:00:01Z', 'request' => 1,
                              'event' => 'SECRET', 'payload' => 'SECRET'))
      file.flush
      output, = capture_io { PiStallLab::Trace.observe(file.path) }

      assert_equal "2026-09-23T00:00:00Z request=1 request_prepared\n", output
    end
  end

  def test_invalid_json_does_not_echo_private_line
    Tempfile.create(['pi-session-', '.jsonl']) do |file|
      file.puts('{"private":"SECRET", broken')
      file.flush
      message = begin
        PiStallLab::Trace.replay(file.path)
      rescue ArgumentError => e
        e.message
      end

      assert_equal 'invalid session JSONL at line 1', message
    end
  end

  def test_does_not_classify_aborts_with_visible_output
    assistant = event('assistant', '2026-09-23T00:03:07Z',
                      stop_reason: 'aborted', content: [{ 'text' => 'partial output' }])
    rows = [event('user', '2026-09-23T00:00:00Z'), assistant]

    assert_equal [], PiStallLab::Trace.stalled_intervals(rows)
  end
end
