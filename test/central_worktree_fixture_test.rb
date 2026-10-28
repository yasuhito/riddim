# frozen_string_literal: true

require_relative 'central_worktree_context_test'

# Exercise the context harness with disposable executables, not a live Pi.
class CentralWorktreeFixtureTest < Minitest::Test
  # rubocop:disable-next Metrics/MethodLength
  def install_pi(root, port, mode)
    File.write(File.join(root, 'pi'), <<~RUBY, perm: 0o700)
      #!#{RbConfig.ruby}
      require 'socket'
      File.write(#{File.join(root, 'pid').dump}, Process.pid.to_s)
      socket = TCPSocket.new('127.0.0.1', #{port})
      body = '{"messages":[{"role":"system","content":"fixture"}]}'
      socket.write("POST /v1/chat/completions HTTP/1.1\\r\\nContent-Length: \#{body.bytesize}\\r\\n\\r\\n\#{body}")
      socket.read
      socket.close
      if #{mode.dump} == 'pressure'
        STDERR.write('diagnostic pressure ' * 32_768)
        STDERR.puts('CONTEXT_FIXTURE_DIAGNOSTIC')
        exit 23
      end
      STDOUT.close
      STDERR.puts('CONTEXT_FIXTURE_NONEXIT')
      STDERR.close
      sleep 60
    RUBY
  end

  # rubocop:disable-next Metrics/MethodLength
  def with_context_fixture(mode)
    Dir.mktmpdir('riddim-context-fixture-') do |root|
      server = TCPServer.new('127.0.0.1', 0)
      install_pi(root, server.addr[1], mode)
      harness = CentralWorktreeContextTest.new('fixture')
      harness.instance_variable_set(:@root, root)
      harness.instance_variable_set(:@home, root)
      harness.instance_variable_set(:@worker, root)
      harness.instance_variable_set(:@server, server)
      environment = harness.pi_environment.merge('PATH' => root)
      harness.define_singleton_method(:pi_environment) { environment }
      yield harness, root
    ensure
      server&.close
    end
  end

  def assert_reaped(root)
    pid = Integer(File.read(File.join(root, 'pid')))
    assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
    assert_raises(Errno::ECHILD) { Process.waitpid(pid, Process::WNOHANG) }
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_stderr_pressure_is_drained_and_failure_diagnostics_retained
    with_context_fixture('pressure') do |harness, root|
      error = assert_raises(RuntimeError) { Timeout.timeout(25) { harness.request_context } }

      assert_includes error.message, 'Pi startup failed:'
      assert_includes error.message, 'CONTEXT_FIXTURE_DIAGNOSTIC'
      assert_reaped(root)
    end
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_nonexiting_child_with_closed_pipes_is_bounded_and_reaped
    with_context_fixture('nonexit') do |harness, root|
      error = assert_raises(RuntimeError) { Timeout.timeout(25) { harness.request_context } }

      assert_includes error.message, 'Pi context timed out:'
      assert_includes error.message, 'CONTEXT_FIXTURE_NONEXIT'
      assert_reaped(root)
    end
  end
end
