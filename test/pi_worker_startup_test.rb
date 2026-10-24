# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative '../scripts/pi_stall_server'

# Auto-discovered project extensions, a real Pi startup and a loopback model.
class PiWorkerStartupTest < Minitest::Test
  SOURCE = File.expand_path('..', __dir__)

  def setup
    skip 'Pi executable unavailable on PATH' unless ENV.fetch('PATH').split(File::PATH_SEPARATOR).any? do |dir|
      File.executable?(File.join(dir, 'pi')) && File.file?(File.join(dir, 'pi'))
    end
  end

  # rubocop:disable-next Metrics/MethodLength
  def prepare_project(root)
    project = File.join(root, 'project')
    extensions = File.join(project, '.pi/extensions')
    FileUtils.mkdir_p(extensions)
    FileUtils.mkdir_p(File.join(project, 'bin'))
    FileUtils.cp(File.join(SOURCE, '.pi/extensions/riddim-notifications.ts'), extensions)
    File.symlink(File.join(SOURCE, 'bin/riddim'), File.join(project, 'bin/riddim'))
    # Another startup handler can await I/O before the positional brief. Pin
    # this order after the notification extension without fabricating a wake.
    File.write(File.join(extensions, 'zzz-slow-start.ts'), <<~TS)
      export default function(pi) {
        pi.on('session_start', async () => {
          console.error('startup ordering pinned');
          await new Promise(r => setTimeout(r, 700));
        });
      }
    TS
    project
  end

  def respond(server)
    socket = PiStallLab::LabServer.receive_request(server)
    sleep 1 # Keep any injected follow-up busy until positional submission.
    PiStallLab::LabServer.send_ok(socket)
  rescue Errno::EPIPE, Errno::ECONNRESET
    # Broken startup aborts its pre-brief model request.
  ensure
    socket&.close
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def exercise_startup(root, state, server)
    env = { 'PI_CODING_AGENT_DIR' => root, 'PI_OFFLINE' => '1', 'PI_TELEMETRY' => '0',
            'RIDDIM_STATE_DIR' => state, 'RIDDIM_ACTOR' => 'branch' }
    args = %w[--mode json --print --no-tools --no-skills --no-prompt-templates --no-context-files --approve]
    args += ['--session-dir', root, '--model', 'stall-lab/test', '--thinking', 'off', 'INITIAL WORKER BRIEF']
    Bundler.with_unbundled_env do
      Open3.popen3(env, 'pi', *args, chdir: prepare_project(root)) do |input, output, error, wait|
        input.close
        responder = Thread.new { respond(server) }
        text = Timeout.timeout(30) { output.read }
        diagnostics = error.read
        responder.join

        assert_predicate wait.value, :success?, diagnostics
        assert_includes diagnostics, 'startup ordering pinned'
        refute_includes diagnostics, 'already processing'
        assert_includes text, 'INITIAL WORKER BRIEF'
        refute_includes text, 'Riddim watcher FAILED'
        refute_path_exists File.join(state, '.notification-watcher.lock')
      ensure
        Process.kill('TERM', wait.pid) if wait.alive?
        responder&.kill
      end
    end
  end

  # rubocop:disable-next Metrics/MethodLength
  def test_marked_worker_initial_brief_survives_supervisor_lock_collision
    Dir.mktmpdir('riddim-worker-startup-') do |root|
      state = File.join(root, 'state')
      FileUtils.mkdir_p(state)
      server = TCPServer.new('127.0.0.1', 0)
      PiStallLab::LabServer.config(root, server.addr[1])
      File.open(state, File::RDONLY) do |lock|
        lock.flock(File::LOCK_EX)
        exercise_startup(root, state, server)
      end
    ensure
      server&.close
    end
  end
end
