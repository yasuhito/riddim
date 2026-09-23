# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../scripts/pi_stall_lab'

class PiStallHeadersOnlyTest < Minitest::Test
  def write_private_trace(root, names)
    File.write(File.join(root, 'trace.jsonl'), names.map { |name| "#{JSON.generate('event' => name)}\n" }.join,
               mode: 'w', perm: 0o600)
  end

  def with_running_child
    pid = Process.spawn('sleep', '5')
    yield pid
  ensure
    PiStallLab::Reproducer.stop_owned_pi(pid)
  end

  def captured_check_error(pid, output, root)
    PiStallLab::Reproducer.check_headers_only(pid, output, root, 0.1)
  rescue RuntimeError => e
    e.message
  end

  def headers_only_output(root)
    stdout = File.join(root, 'stdout')
    File.write(stdout, '', mode: 'w', perm: 0o600)
    write_private_trace(root, %w[session_start agent_start turn_start request_prepared response_headers])
    pid = Process.spawn('sleep', '5')
    capture_io { PiStallLab::Reproducer.check_headers_only(pid, stdout, root, 0.1) }.first
  ensure
    PiStallLab::Reproducer.stop_owned_pi(pid)
  end

  def test_accepts_headers_without_updates
    Dir.mktmpdir do |root|
      output = headers_only_output(root)

      assert_equal 'headers_only: request received, response headers received, no updates for 0.1s, ' \
                   "Pi still running\n", output
    end
  end

  def test_rejects_premature_updates
    Dir.mktmpdir do |root|
      stdout = File.join(root, 'stdout')
      File.write(stdout, '', mode: 'w', perm: 0o600)
      write_private_trace(root, %w[request_prepared response_headers first_update])
      with_running_child do |pid|
        error = captured_check_error(pid, stdout, root)

        assert_equal 'unexpected trace boundaries', error
      end
    end
  end

  def test_rejects_turn_completion_without_updates
    assert_equal 'unexpected trace boundaries', check_with_extra_event('turn_end')
  end

  def test_rejects_agent_settlement_without_updates
    assert_equal 'unexpected trace boundaries', check_with_extra_event('agent_settled')
  end

  def check_with_extra_event(event)
    Dir.mktmpdir do |root|
      stdout = File.join(root, 'stdout')
      File.write(stdout, '', mode: 'w', perm: 0o600)
      write_private_trace(root, %W[request_prepared response_headers #{event}])
      with_running_child { |pid| return captured_check_error(pid, stdout, root) }
    end
  end

  def test_rejects_response_body_without_updates
    Dir.mktmpdir do |root|
      stdout = File.join(root, 'stdout')
      File.write(stdout, 'OK', mode: 'w', perm: 0o600)
      write_private_trace(root, %w[request_prepared response_headers])
      with_running_child do |pid|
        error = captured_check_error(pid, stdout, root)

        assert_equal 'Pi printed a response without SSE body bytes', error
      end
    end
  end

  def test_rejects_exited_pi
    Dir.mktmpdir do |root|
      stdout = File.join(root, 'stdout')
      File.write(stdout, '', mode: 'w', perm: 0o600)
      write_private_trace(root, %w[request_prepared response_headers])
      pid = Process.spawn('true')
      Process.waitpid(pid)
      error = captured_check_error(pid, stdout, root)

      assert_equal 'Pi exited before the headers-only interval finished', error
    end
  end

  def test_server_sends_no_body_after_headers
    server = TCPServer.new('127.0.0.1', 0)
    client = TCPSocket.new('127.0.0.1', server.addr[1])
    accepted = server.accept
    PiStallLab::LabServer.send_headers_only(accepted)
    accepted.close
    headers = client.read

    assert_equal "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n", headers
  ensure
    client&.close
    server&.close
  end
end
