# frozen_string_literal: true

require 'English'
require 'json'
require 'timeout'
require 'tmpdir'
require_relative 'pi_stall_session'
require_relative 'pi_stall_server'

# Isolated Pi/API stall reproduction and metadata-only session inspection.
module PiStallLab
  # Runs real Pi against a loopback-only OpenAI-compatible endpoint.
  module Reproducer
    module_function

    def spawn_pi(root, output, error)
      env = { 'PI_CODING_AGENT_DIR' => root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
              'RIDDIM_PI_TRACE_FILE' => File.join(root, 'trace.jsonl') }
      extension = File.expand_path('pi_stall_trace.ts', __dir__)
      Process.spawn(env, 'pi', '--print', '--no-tools', '--no-extensions', '--no-skills', '--no-prompt-templates',
                    '--no-context-files', '--extension', extension, '--session-dir', root,
                    '--model', 'stall-lab/test', '--thinking', 'off', 'Reply with exactly OK.',
                    out: output, err: error)
    end

    def alive?(pid)
      Process.waitpid(pid, Process::WNOHANG).nil?
    rescue Errno::ECHILD
      false
    end

    def stop_owned_pi(pid)
      return unless alive?(pid)

      Process.kill('INT', pid)
      Timeout.timeout(5) { Process.waitpid(pid) }
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    rescue Timeout::Error
      Process.kill('KILL', pid)
      Process.waitpid(pid)
    end

    def events(root)
      path = File.join(root, 'trace.jsonl')
      raise 'trace is not private' unless File.stat(path).mode & 0o777 == 0o600

      File.foreach(path).map { |line| JSON.parse(line).fetch('event') }
    end

    def check_healthy(pid, output, root)
      Timeout.timeout(20) { sleep 0.1 while alive?(pid) }
      raise 'healthy Pi failed' unless $CHILD_STATUS.success? && File.read(output).strip == 'OK'
      raise 'missing healthy request boundaries' unless
        (events(root) & %w[request_prepared response_headers first_update turn_end]).size == 4

      puts 'healthy: request received, response headers, first update, turn ended, Pi exited with OK'
    end

    def check_silent(pid, output, root, seconds)
      sleep seconds
      raise 'Pi exited before the silent interval finished' unless alive?(pid)
      raise 'Pi printed a response without API bytes' unless File.empty?(output)

      observed = events(root) & %w[request_prepared response_headers first_update]
      raise 'unexpected trace boundaries' unless observed == %w[request_prepared]

      puts "silent: request received, Pi prepared request, no headers or updates for #{seconds}s, Pi still running"
    end

    def prepare(root)
      server = TCPServer.new('127.0.0.1', 0)
      LabServer.config(root, server.addr[1])
      output = File.join(root, 'stdout')
      [server, spawn_pi(root, output, File.join(root, 'stderr')), output]
    rescue StandardError
      server&.close
      raise
    end

    def with_pi
      Dir.mktmpdir('riddim-pi-stall-') do |root|
        server, pid, output = prepare(root)
        socket = LabServer.receive_request(server)
        yield(pid, socket, output, root)
      ensure
        socket&.close
        server&.close
        stop_owned_pi(pid) if pid
      end
    end

    def run_case(mode, silence: 2)
      with_pi do |pid, socket, output, root|
        if mode == :healthy
          LabServer.send_ok(socket)
          socket.close
          check_healthy(pid, output, root)
        else
          check_silent(pid, output, root, silence)
        end
      end
    end
  end

  def self.run
    case ARGV
    in ['reproduce']
      %i[healthy silent].each { |mode| Reproducer.run_case(mode) }
    in ['replay', String => file]
      Trace.replay(file)
    in ['observe', String => file]
      Trace.observe(file)
    else
      usage
    end
  end

  def self.usage
    warn 'Usage: ruby scripts/pi_stall_lab.rb reproduce | replay <pi-session.jsonl> | observe <trace.jsonl>'
    exit 2
  end
end

PiStallLab.run if $PROGRAM_NAME == __FILE__
